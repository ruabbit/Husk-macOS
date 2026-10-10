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
        try recoverInstall()
        return try body()
    }

    private struct InstallTransaction: Codable {
        let id: String
        let stage: String
        let newDigest: String
        let oldDigest: String?
    }
    private var transactionURL: URL { paths.root.appendingPathComponent(".install-transaction.json") }
    private func directoryDigest(_ directory: URL) throws -> String? {
        guard fm.fileExists(atPath: directory.path) else { return nil }
        return try JSONDecoder().decode(LibraryGame.self, from: Data(contentsOf: directory.appendingPathComponent("game.json"))).digest
    }
    /// Complete or roll back a directory swap interrupted before its index write.
    /// The journal never points outside managed Staging/Games directories.
    private func recoverInstall() throws {
        guard fm.fileExists(atPath: transactionURL.path) else { return }
        let transaction = try JSONDecoder().decode(InstallTransaction.self, from: Data(contentsOf: transactionURL))
        guard Self.validID(transaction.id), UUID(uuidString: transaction.stage) != nil else {
            throw LibraryFailure("安装恢复记录无效，原文件已保留。")
        }
        let stage = paths.root.appendingPathComponent("Staging/\(transaction.stage)")
        let destination = paths.game(transaction.id)
        let indexDigest = try readIndex().games.first(where: { $0.id == transaction.id })?.digest
        let diskDigest = try directoryDigest(destination)
        if indexDigest == transaction.newDigest {
            guard diskDigest == transaction.newDigest else { throw LibraryFailure("安装索引与文件不一致，已保留恢复数据。") }
        } else if indexDigest == transaction.oldDigest {
            if diskDigest == transaction.newDigest {
                if let oldDigest = transaction.oldDigest {
                    guard try directoryDigest(stage) == oldDigest,
                          renamex_np(stage.path, destination.path, UInt32(RENAME_SWAP)) == 0 else {
                        throw LibraryFailure("无法恢复上一个安装版本，恢复数据已保留。")
                    }
                } else { try fm.moveItem(at: destination, to: stage) }
            } else if diskDigest != transaction.oldDigest {
                throw LibraryFailure("无法识别中断的安装，原文件已保留。")
            }
        } else { throw LibraryFailure("安装恢复记录与资料库不一致，原文件已保留。") }
        if fm.fileExists(atPath: stage.path) { try fm.removeItem(at: stage) }
        try fm.removeItem(at: transactionURL)
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

    public func importGame(_ source: URL, blockedIDs: Set<String> = []) throws -> LibraryGame {
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
            defer { if !fm.fileExists(atPath: transactionURL.path) { try? fm.removeItem(at: stage) } }
            var names: [String] = []
            if type == "apk" {
                names = ["base.apk"]
                try fm.copyItem(at: source, to: stage.appendingPathComponent(names[0]))
            } else {
                let apks = try listing(source).entries.filter { $0.name.lowercased().hasSuffix(".apk") }
                guard !apks.isEmpty, apks.count <= 32 else { throw LibraryFailure("此 bundle 需要 1–32 个 APK；无法完整导入该组合。") }
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
            return try finishImport(stage: stage, names: names, sourceName: source.lastPathComponent, index: &index, blockedIDs: blockedIDs)
        }
    }

    /// A Play delivery is one installation, even when its base, ABI and assets
    /// arrive as separate files. Never import its APKs as independent games.
    public func importAPKs(_ sources: [URL], package: String, version: Int, title: String,
                           blockedIDs: Set<String> = []) throws -> LibraryGame {
        try locked {
            guard (1...32).contains(sources.count), version > 0 else { throw LibraryFailure("APK 集合的文件数量或版本无效。") }
            var index = try readIndex()
            let stage = paths.root.appendingPathComponent("Staging/\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)
            defer { if !fm.fileExists(atPath: transactionURL.path) { try? fm.removeItem(at: stage) } }
            var names: [String] = []
            var total = 0
            for source in sources {
                try Task.checkCancellation()
                let name = source.lastPathComponent
                let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
                guard Self.validName(name), name.hasSuffix(".apk"), !names.contains(name),
                      values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize,
                      size > 0, size <= 4 << 30 else { throw LibraryFailure("APK 集合含无效文件。") }
                total += size
                guard total <= 4 << 30 else { throw LibraryFailure("APK 集合超过 4 GB。") }
                try fm.copyItem(at: source, to: stage.appendingPathComponent(name)); names.append(name)
            }
            return try finishImport(stage: stage, names: names, sourceName: "\(package).apks", index: &index,
                                    expectedPackage: package, expectedVersion: version, title: title, blockedIDs: blockedIDs)
        }
    }

    private func finishImport(stage: URL, names: [String], sourceName: String, index: inout LibraryIndex,
                              expectedPackage: String? = nil, expectedVersion: Int? = nil, title: String? = nil,
                              blockedIDs: Set<String> = []) throws -> LibraryGame {
        try Task.checkCancellation()
        var names = names
        let manifests = try names.map { name -> (String, String?, Int?, String?, [String], Bool) in
            let file = stage.appendingPathComponent(name)
            guard let manifest = Self.entry(file, "AndroidManifest.xml") else { throw LibraryFailure("APK 缺少 AndroidManifest.xml。") }
            let split = ApkMetadata.elements(manifest).first(where: { $0.name == "manifest" })?.attributes.first(where: { $0.name == "split" })?.value
            let elements = ApkMetadata.elements(manifest)
            let dependencies = elements.filter { $0.name == "uses-split" }.compactMap {
                $0.attributes.first(where: { $0.name == "name" })?.value
            }
            let required = elements.contains { $0.attributes.contains { $0.name == "isSplitRequired" && $0.data != 0 } }
            return (name, ApkMetadata.packageName(manifest), ApkMetadata.versionCode(manifest), split, dependencies, required)
        }
        let strict = expectedPackage != nil || names.count > 1
        let splitIDs = Set(manifests.compactMap { $0.3 })
        guard manifests.allSatisfy({ Set($0.4).isSubset(of: splitIDs) && (!$0.5 || names.count > 1) }) else {
            throw LibraryFailure("缺少应用声明为必需的分包，原安装未改变。")
        }
        if strict {
            guard let package = manifests[0].1, let version = manifests[0].2,
                  manifests.allSatisfy({ $0.1 == package && $0.2 == version }),
                  expectedPackage == nil || expectedPackage == package,
                  expectedVersion == nil || expectedVersion == version,
                  manifests.filter({ $0.3 == nil || $0.3 == "" }).count == 1,
                  Set(manifests.map { $0.3 ?? "" }).count == manifests.count else {
                throw LibraryFailure("APK 集合的包名、版本或分包身份不一致，原安装未改变。")
            }
            let base = manifests.first(where: { $0.3 == nil || $0.3 == "" })!.0
            names = [base] + names.filter { $0 != base }.sorted()
        }
        let apks = names.map { stage.appendingPathComponent($0) }
        let signing = try apks.map { try APKSignature.verify($0) }
        if strict {
            guard let signer = signing[0], signing.allSatisfy({ $0 == signer }) else {
                throw LibraryFailure("APK 集合必须具有一致且有效的 v2/v3 签名。")
            }
        }
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
        let previous = index.games.first(where: { $0.id == id })
        let version = ApkMetadata.versionCode(androidManifest)
        if let previous {
            guard !blockedIDs.contains(id) else { throw LibraryFailure("请先结束此应用，再安装更新。") }
            let oldAPKs = previous.apkNames.map { paths.game(id).appendingPathComponent($0) }
            guard try oldAPKs.map(Self.digest).joined(separator: ":") == previous.digest,
                  let oldSigner = try APKSignature.verify(oldAPKs[0]), let signer = signing[0], oldSigner == signer,
                  let oldManifest = Self.entry(oldAPKs[0], "AndroidManifest.xml"),
                  let oldVersion = ApkMetadata.versionCode(oldManifest), let version, version > oldVersion else {
                throw LibraryFailure("更新必须使用相同签名且版本更高的完整 APK 集合；旧应用和存档已保留。")
            }
        } else if fm.fileExists(atPath: paths.game(id).path) { throw LibraryFailure("应用目录已存在但未登记，原文件已保留。") }
        var game = LibraryGame(id: id, title: fixture?.title ?? metadata.label ?? title ?? URL(fileURLWithPath: sourceName).deletingPathExtension().lastPathComponent,
                               importedAt: Date(), sourceName: sourceName, apkNames: names, digest: digest,
                               engine: fixture != nil ? "Husk Orbit" : report.engine, abis: report.abis, fixture: fixture,
                               settings: GameSettings(), lastPlayed: nil)
        game.packageName = packageID; game.versionCode = version; game.signerSHA256 = signing[0]
        if let previous { game.settings = previous.settings; game.lastPlayed = previous.lastPlayed }
        if let iconName = fixture?.icon ?? metadata.iconEntry, let data = Self.entry(base, iconName, limit: 4 << 20) {
            try data.write(to: stage.appendingPathComponent("icon.data"))
        }
        try reportData.write(to: stage.appendingPathComponent("scan.json"))
        try encoder.encode(game).write(to: stage.appendingPathComponent("game.json"))
        try Task.checkCancellation()
        let destination = paths.game(id)
        let transaction = InstallTransaction(id: id, stage: stage.lastPathComponent, newDigest: game.digest, oldDigest: previous?.digest)
        try AtomicFile.write(encoder.encode(transaction), to: transactionURL)
        do {
            if let position = index.games.firstIndex(where: { $0.id == id }) {
                guard renamex_np(stage.path, destination.path, UInt32(RENAME_SWAP)) == 0 else {
                    throw LibraryFailure("无法替换旧应用，原安装已保留。")
                }
                index.games[position] = game
            } else {
                try fm.moveItem(at: stage, to: destination); index.games.append(game)
            }
            try AtomicFile.write(encoder.encode(index), to: paths.index)
            try recoverInstall()
        } catch {
            try? recoverInstall()
            throw error
        }
        return game
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
        let (game, apks, package) = try prepareVMSet(id)
        guard apks.count == 1 else { throw LibraryFailure("请使用完整 APK 集合安装此应用。") }
        return (game, apks[0], package)
    }
    public func prepareVMSet(_ id: String) throws -> (LibraryGame, [URL], String) {
        try locked {
            guard let game = try readIndex().games.first(where: { $0.id == id }), (1...32).contains(game.apkNames.count) else {
                throw LibraryFailure("Android VM 的 APK 集合不完整。")
            }
            let apks = game.apkNames.map { paths.game(id).appendingPathComponent($0) }
            let apk = apks[0]
            guard try apks.map(Self.digest).joined(separator: ":") == game.digest else { throw LibraryFailure("游戏文件已经改变，请重新导入。") }
            guard let data = Self.entry(apk, "AndroidManifest.xml", limit: 8 << 20),
                  let manifest = ApkMetadata.elements(data).first(where: { $0.name == "manifest" }),
                  let package = manifest.attributes.first(where: { $0.name == "package" && $0.dataType == 3 })?.value,
                  !package.isEmpty, package.range(of: "^[A-Za-z0-9_.$]+$", options: .regularExpression) != nil else {
                throw LibraryFailure("APK 中缺少有效的 Android package 名称。")
            }
            return (game, apks, package)
        }
    }
}
