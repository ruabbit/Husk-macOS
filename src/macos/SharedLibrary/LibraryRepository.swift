// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import CryptoKit
import HuskCore
import Darwin

private struct ArchiveListing: Decodable {
    struct Entry: Decodable { let name: String; let size: UInt64; let method: Int }
    let error: String?
    let entries: [Entry]
}
private struct Scan: Decodable {
    let ok: Bool
    let error: String?
    let hasManifest: Bool
    let verdict: String
    let engine: String?
    let abis: [String]
}

public actor LibraryRepository {
    public nonisolated let paths: LibraryPaths
    private let trustedFixtureHash: String
    private let fm = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder
    }()

    public init(paths: LibraryPaths = LibraryPaths(), trustedFixtureHash: String) throws {
        self.paths = paths
        self.trustedFixtureHash = trustedFixtureHash
        for name in ["Games", "Saves", "Logs", "Staging", "Trash"] {
            try FileManager.default.createDirectory(at: paths.root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        let fd = open(paths.root.appendingPathComponent(".library.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw LibraryFailure("无法锁定资料库。") }
        defer { flock(fd, LOCK_UN); close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw LibraryFailure("资料库正由另一个 Husk 进程使用，请稍后重试。") }
        return try body()
    }

    private func readIndex() throws -> LibraryIndex {
        guard fm.fileExists(atPath: paths.index.path) else { return LibraryIndex() }
        do {
            let result = try JSONDecoder().decode(LibraryIndex.self, from: Data(contentsOf: paths.index))
            guard result.schema == 1, Set(result.games.map(\.id)).count == result.games.count,
                  result.games.allSatisfy({ Self.validID($0.id) && $0.apkNames.allSatisfy(Self.validName) })
            else { throw LibraryFailure("资料库格式不受支持；原文件已保留。") }
            return result
        } catch { throw LibraryFailure("无法读取资料库；原文件已保留。\(error.localizedDescription)") }
    }

    public func games() throws -> [LibraryGame] { try locked { try readIndex().games } }

    public static func digest(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func validID(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isASCII && ($0.isNumber || ("a"..."f").contains(String($0))) }
    }
    private static func validName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
    }

    public static func entry(_ path: URL, _ name: String, limit: Int = 16 << 20) -> Data? {
        var count = 0
        guard let bytes = husk_tl_read_entry(path.path, name, limit, &count) else { return nil }
        defer { husk_tl_free(bytes) }
        return Data(bytes: bytes, count: count)
    }

    private func listing(_ file: URL) throws -> ArchiveListing {
        guard let raw = husk_archive_entries(file.path) else { throw LibraryFailure("无法读取压缩包。") }
        defer { husk_tl_free(raw) }
        let list = try JSONDecoder().decode(ArchiveListing.self, from: Data(String(cString: raw).utf8))
        if let error = list.error { throw LibraryFailure("压缩包损坏：\(error)") }
        guard list.entries.count <= 50_000, Set(list.entries.map(\.name)).count == list.entries.count,
              list.entries.allSatisfy({ $0.size <= 512 << 20 && [0, 8].contains($0.method) }),
              list.entries.reduce(UInt64(0), { $0 + $1.size }) <= 4 << 30
        else { throw LibraryFailure("压缩包含重复条目、过大的内容或不支持的压缩方式。") }
        return list
    }

    private func scan(_ apks: [URL]) throws -> (Scan, Data) {
        let strings = apks.map { strdup($0.path) }
        defer { strings.forEach { free($0) } }
        let pointers: [UnsafePointer<CChar>?] = strings.map { $0.map { UnsafePointer($0) } }
        guard let raw = pointers.withUnsafeBufferPointer({ husk_tl_scan($0.baseAddress, Int32($0.count)) })
        else { throw LibraryFailure("扫描失败。") }
        defer { husk_tl_free(raw) }
        let data = Data(String(cString: raw).utf8)
        let report = try JSONDecoder().decode(Scan.self, from: data)
        guard report.ok, report.hasManifest else { throw LibraryFailure("不是有效的 Android 应用：\(report.error ?? "缺少 AndroidManifest.xml")") }
        return (report, data)
    }

    public func importGame(_ source: URL) throws -> LibraryGame {
        try locked {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            let type = source.pathExtension.lowercased()
            guard type == "apk" || BundleUnpacker.extensions.contains(type) else { throw LibraryFailure("请选择 APK、XAPK、APKM 或 APKS 文件。") }
            let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= 4 << 30
            else { throw LibraryFailure("导入文件必须是小于 4 GB 的普通文件。") }
            var index = try readIndex()
            let stage = paths.root.appendingPathComponent("Staging/\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: stage) }
            var names: [String] = []
            if type == "apk" {
                names = ["base.apk"]
                try fm.copyItem(at: source, to: stage.appendingPathComponent(names[0]))
            } else {
                let apks = try listing(source).entries.filter { $0.name.lowercased().hasSuffix(".apk") }
                guard !apks.isEmpty, apks.count <= 4 else { throw LibraryFailure("此 bundle 需要 1–4 个 APK；当前版本无法完整导入该组合。") }
                for entry in apks {
                    let name = (entry.name as NSString).lastPathComponent
                    guard Self.validName(name), !names.contains(where: { $0.lowercased() == name.lowercased() })
                    else { throw LibraryFailure("Bundle 含冲突的 APK 文件名。") }
                    var error = [CChar](repeating: 0, count: 512)
                    guard husk_archive_extract(source.path, entry.name, stage.appendingPathComponent(name).path, &error, error.count)
                    else { throw LibraryFailure("解包失败：\(String(cString: error))") }
                    names.append(name)
                }
                let siblings = names
                names.sort { let a = BundleUnpacker.rank($0, siblings: siblings), b = BundleUnpacker.rank($1, siblings: siblings); return a == b ? $0 < $1 : a < b }
            }
            let apks = names.map { stage.appendingPathComponent($0) }
            for apk in apks { _ = try listing(apk) }
            let (report, reportData) = try scan(apks)
            let digest = try apks.map(Self.digest).joined(separator: ":")
            if let duplicate = index.games.first(where: { $0.digest == digest }) { return duplicate }
            let base = apks[0]
            let androidManifest = Self.entry(base, "AndroidManifest.xml") ?? Data()
            let resources = Self.entry(base, "resources.arsc", limit: 64 << 20) ?? Data()
            let metadata = ApkMetadata.read(manifest: androidManifest, resources: resources)
            let fixtureData = Self.entry(base, "assets/husk-fixture.json", limit: 16_384)
            let candidate = fixtureData.flatMap { try? JSONDecoder().decode(FixtureManifest.self, from: $0) }
            var fixture: FixtureManifest?
            if let candidate, candidate.schema == 1, candidate.abi == 1,
               candidate.library == "libhusk_orbit.so", (0...1).contains(candidate.variant),
               candidate.id == "org.husk.orbit.\(candidate.variant)",
               let library = Self.entry(base, "lib/arm64-v8a/\(candidate.library)", limit: 4 << 20),
               SHA256.hash(data: library).map({ String(format: "%02x", $0) }).joined() == trustedFixtureHash {
                fixture = candidate
            }
            let packageID = ApkMetadata.elements(androidManifest).first(where: { $0.name == "manifest" })?
                .attributes.first(where: { $0.name == "package" })?.value
            let identity = fixture?.id ?? packageID ?? digest
            let id = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
            guard !index.games.contains(where: { $0.id == id }), !fm.fileExists(atPath: paths.game(id).path)
            else { throw LibraryFailure("资料库已有此应用的另一版本。请先移除旧版本；存档会保留。") }
            let game = LibraryGame(id: id, title: fixture?.title ?? metadata.label ?? source.deletingPathExtension().lastPathComponent,
                                   importedAt: Date(), sourceName: source.lastPathComponent, apkNames: names, digest: digest,
                                   engine: fixture != nil ? "Husk Orbit" : report.engine, abis: report.abis, fixture: fixture,
                                   settings: GameSettings(), lastPlayed: nil)
            if let iconName = fixture?.icon ?? metadata.iconEntry, let data = Self.entry(base, iconName, limit: 4 << 20) {
                try data.write(to: stage.appendingPathComponent("icon.data"))
            }
            try reportData.write(to: stage.appendingPathComponent("scan.json"))
            try encoder.encode(game).write(to: stage.appendingPathComponent("game.json"))
            try fm.moveItem(at: stage, to: paths.game(id))
            index.games.append(game)
            do { try AtomicFile.write(encoder.encode(index), to: paths.index) }
            catch { try? fm.moveItem(at: paths.game(id), to: stage); throw error }
            return game
        }
    }

    public func update(_ id: String, settings: GameSettings? = nil, played: Bool = false,
                       muted: Bool? = nil, pauseWhenInactive: Bool? = nil) throws {
        try locked {
            var index = try readIndex()
            guard let position = index.games.firstIndex(where: { $0.id == id }) else { throw LibraryFailure("游戏已移除。") }
            if let settings { index.games[position].settings = settings }
            if let muted { index.games[position].settings.muted = muted }
            if let pauseWhenInactive { index.games[position].settings.pauseWhenInactive = pauseWhenInactive }
            if played { index.games[position].lastPlayed = Date() }
            try AtomicFile.write(encoder.encode(index), to: paths.index)
        }
    }

    /// Removal preserves Saves/<id>; reimporting the same package restores it.
    public func remove(_ id: String) throws {
        try locked {
            var index = try readIndex()
            guard Self.validID(id), index.games.contains(where: { $0.id == id }) else { throw LibraryFailure("游戏不存在。") }
            let quarantine = paths.root.appendingPathComponent("Trash/\(UUID().uuidString)")
            let existing = fm.fileExists(atPath: paths.game(id).path)
            if existing { try fm.moveItem(at: paths.game(id), to: quarantine) }
            index.games.removeAll { $0.id == id }
            do { try AtomicFile.write(encoder.encode(index), to: paths.index) }
            catch { if existing { try? fm.moveItem(at: quarantine, to: paths.game(id)) }; throw error }
            if existing { try? fm.removeItem(at: quarantine) }
        }
    }

    public func deleteSave(_ id: String) throws {
        try locked {
            guard Self.validID(id) else { throw LibraryFailure("无效的游戏标识。") }
            if fm.fileExists(atPath: paths.save(id).path) { try fm.removeItem(at: paths.save(id)) }
        }
    }

    public func prepare(_ id: String) throws -> (LibraryGame, [URL], URL) {
        try locked {
            guard let game = try readIndex().games.first(where: { $0.id == id }), game.playable else { throw LibraryFailure("此游戏当前无法运行。") }
            let apks = game.apkNames.map { paths.game(id).appendingPathComponent($0) }
            guard try apks.map(Self.digest).joined(separator: ":") == game.digest else { throw LibraryFailure("游戏文件已改变或损坏，请重新导入。") }
            try fm.createDirectory(at: paths.save(id), withIntermediateDirectories: true)
            return (game, apks, paths.checkpoint(id))
        }
    }

    public func prepareVM(_ id: String) throws -> (LibraryGame, URL, String) {
        try locked {
            guard let game = try readIndex().games.first(where: { $0.id == id }), game.apkNames.count == 1 else {
                throw LibraryFailure("Android VM 当前需要单个 APK；split bundle 安装尚未接入。")
            }
            let apk = paths.game(id).appendingPathComponent(game.apkNames[0])
            guard try Self.digest(apk) == game.digest else { throw LibraryFailure("游戏文件已经改变，请重新导入。") }
            guard let data = Self.entry(apk, "AndroidManifest.xml", limit: 8 << 20),
                  let manifest = ApkMetadata.elements(data).first(where: { $0.name == "manifest" }),
                  let package = manifest.attributes.first(where: { $0.name == "package" && $0.dataType == 3 })?.value,
                  !package.isEmpty, package.range(of: "^[A-Za-z0-9_.$]+$", options: .regularExpression) != nil else {
                throw LibraryFailure("APK 中缺少有效的 Android package 名称。")
            }
            return (game, apk, package)
        }
    }
}
