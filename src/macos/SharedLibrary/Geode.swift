// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Darwin
import HuskCore

public enum Geode {
    public static let gamePackage = "com.robtopx.geometryjump"
    public static let launcherPackage = "com.geode.launcher"
    static let releaseName = "geode-android64.zip", launcherName = "geode-launcher.apk", resourcesName = "geode-resources.zip"
    public struct Installation: Codable, Sendable {
        public let schema: Int
        public let version: String
        public let versionCode: Int
        public let gameDigest: String
        public let files: [String: String]
    }
    public static func supports(_ game: LibraryGame) -> Bool {
        game.packageName == gamePackage && game.runtime == "cocos"
    }
    public static func directory(apk: URL) -> URL { apk.deletingLastPathComponent().appendingPathComponent("geode", isDirectory: true) }
    static func regular(_ file: URL) throws {
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= 256 << 20 else {
            throw LibraryFailure("Geode 文件缺失、过大或不是普通文件。")
        }
    }
    static func entries(_ file: URL) throws -> [String] {
        try regular(file)
        guard let raw = husk_archive_entries(file.path) else { throw LibraryFailure("无法读取 Geode 压缩包。") }
        defer { husk_tl_free(raw) }
        guard let object = try JSONSerialization.jsonObject(with: Data(String(cString: raw).utf8)) as? [String: Any],
              object["error"] is NSNull, let entries = object["entries"] as? [[String: Any]], !entries.isEmpty, entries.count < 100_000 else {
            throw LibraryFailure("Geode 下载不是有效的压缩包。")
        }
        var names = Set<String>(), total = 0
        for entry in entries {
            guard let name = entry["name"] as? String, !name.hasPrefix("/"), !name.contains("\\"),
                  !name.split(separator: "/").contains(".."), names.insert(name).inserted,
                  let size = entry["size"] as? Int, size >= 0, size <= 128 << 20 else {
                throw LibraryFailure("Geode 压缩包包含不安全或过大的条目。")
            }
            total += size
            guard total <= 512 << 20 else { throw LibraryFailure("Geode 解压大小超过限制。") }
        }
        return Array(names)
    }
    static func arm64(_ file: URL, entry: String) throws {
        guard let data = LibraryRepository.entry(file, entry, limit: 128 << 20), data.count >= 64,
              Array(data.prefix(6)) == [0x7f, 0x45, 0x4c, 0x46, 2, 1], data[18] == 183, data[19] == 0 else {
            throw LibraryFailure("Geode 下载缺少有效的 arm64 库：\(entry)。")
        }
    }
    static func needsResources(_ version: String) throws -> Bool {
        let digits = version.hasPrefix("v") ? version.dropFirst() : Substring(version)
        guard let first = digits.split(separator: ".").first, let major = Int(first), major > 0 else {
            throw LibraryFailure("无法识别 Geode 版本。")
        }
        return major >= 5
    }
    static func validateFiles(_ folder: URL, version: String) throws -> [String] {
        let release = folder.appendingPathComponent(releaseName), launcher = folder.appendingPathComponent(launcherName)
        let names = try entries(release)
        try arm64(release, entry: "Geode.android64.so")
        _ = try entries(launcher)
        try arm64(launcher, entry: "lib/arm64-v8a/libc++_shared.so")
        var files = [releaseName, launcherName]
        if try needsResources(version) {
            let resources = folder.appendingPathComponent(resourcesName)
            guard try entries(resources).contains(where: { !$0.contains("/") }) else {
                throw LibraryFailure("Geode 5 资源包为空。")
            }
            files.append(resourcesName)
        } else if !names.contains(where: { $0.hasPrefix("resources/") && !$0.hasSuffix("/") }) {
            throw LibraryFailure("Geode 4 发布包缺少内嵌资源。")
        }
        return files
    }
    public static func installed(game: LibraryGame, apk: URL) throws -> Installation {
        guard supports(game) else { throw LibraryFailure("此游戏不能使用 Geode。") }
        let folder = directory(apk: apk), manifest = folder.appendingPathComponent("installation.json")
        let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw LibraryFailure("Geode 缓存目录无效。") }
        try regular(manifest)
        guard (try manifest.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0 <= 32768 else { throw LibraryFailure("Geode 安装记录过大。") }
        let record = try JSONDecoder().decode(Installation.self, from: Data(contentsOf: manifest))
        guard record.schema == 1, record.versionCode == game.versionCode, record.gameDigest == game.digest else {
            throw LibraryFailure("游戏已更新，请重新下载与其版本匹配的 Geode。")
        }
        let names = try validateFiles(folder, version: record.version)
        guard Set(names) == Set(record.files.keys) else { throw LibraryFailure("Geode 文件清单不完整。") }
        for name in names {
            guard try LibraryRepository.digest(folder.appendingPathComponent(name)) == record.files[name] else {
                throw LibraryFailure("Geode 文件已改变或损坏，请重新下载。")
            }
        }
        return record
    }
    public static func arguments(game: LibraryGame, apk: URL) throws -> [String] {
        guard game.settings.geode else { return [] }
        _ = try installed(game: game, apk: apk)
        return ["--geode-directory", directory(apk: apk).path]
    }
    /// Commit only a complete, checked download. Saves and installed mods live elsewhere.
    static func install(game: LibraryGame, apk: URL, version: String, staged: URL) throws -> Installation {
        guard supports(game), let versionCode = game.versionCode, versionCode > 0, versionCode <= Int32.max else { throw LibraryFailure("无法读取 Geometry Dash 版本。") }
        var hashes: [String: String] = [:]
        for name in try validateFiles(staged, version: version) { hashes[name] = try LibraryRepository.digest(staged.appendingPathComponent(name)) }
        let record = Installation(schema: 1, version: version, versionCode: versionCode, gameDigest: game.digest, files: hashes)
        try AtomicFile.write(JSONEncoder().encode(record), to: staged.appendingPathComponent("installation.json"))
        let folder = directory(apk: apk), fm = FileManager.default
        if fm.fileExists(atPath: folder.path) {
            // Both directories are on the same volume. An interrupted update
            // leaves either the old complete cache or the new complete cache.
            guard renamex_np(staged.path, folder.path, UInt32(RENAME_SWAP)) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            try? fm.removeItem(at: staged)
        } else { try fm.moveItem(at: staged, to: folder) }
        return record
    }
    public static func prepare(game: LibraryGame, apk: URL, launcher: URL? = nil,
                               checkForUpdates: Bool = false, session: URLSession = .shared) async throws -> Installation {
        guard supports(game), let versionCode = game.versionCode, versionCode > 0, versionCode <= Int32.max else { throw LibraryFailure("无法读取 Geometry Dash 版本。") }
        // A complete, matching installation remains usable offline.
        if !checkForUpdates, let record = try? installed(game: game, apk: apk) { return record }
        let (version, release) = try await GeodeRelease.latest(versionCode: versionCode, session: session)
        if let record = try? installed(game: game, apk: apk), record.version == version { return record }
        let staged = apk.deletingLastPathComponent().appendingPathComponent(".geode-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: staged, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staged) }
        try await download(release, to: staged.appendingPathComponent(releaseName), session: session)
        if try needsResources(version) {
            let tag = version.hasPrefix("v") ? version : "v" + version
            try await download(URL(string: "https://github.com/geode-sdk/geode/releases/download/\(tag)/resources.zip")!,
                               to: staged.appendingPathComponent(resourcesName), session: session)
        }
        if let launcher, (try? arm64(launcher, entry: "lib/arm64-v8a/libc++_shared.so")) != nil {
            try fm.copyItem(at: launcher, to: staged.appendingPathComponent(launcherName))
        } else {
            let url = try await GeodeRelease.launcherURL(session: session)
            try await download(url, to: staged.appendingPathComponent(launcherName), session: session)
        }
        try Task.checkCancellation()
        return try install(game: game, apk: apk, version: version, staged: staged)
    }
    private static func download(_ url: URL, to destination: URL, session: URLSession) async throws {
        var request = URLRequest(url: url); request.timeoutInterval = 120
        request.setValue("Husk", forHTTPHeaderField: "User-Agent")
        let (temporary, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard (response as? HTTPURLResponse)?.statusCode == 200, response.url?.scheme == "https" else {
            throw LibraryFailure("Geode 下载失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)）。")
        }
        try Task.checkCancellation(); try regular(temporary)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}
