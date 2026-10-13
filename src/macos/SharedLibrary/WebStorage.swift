// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import CryptoKit
import HuskCore

/// WebKit owns its database files. Saves contains the stable, private store ID;
/// removal must run in WebRunner, whose bundle owns that WebKit data directory.
public enum WebStorage {
    public static func helper(in app: URL) -> URL {
        app.appendingPathComponent("Contents/Helpers/WebRunner.app/Contents/MacOS/WebRunner")
    }
    public static func identifier(in save: URL) throws -> UUID {
        let file = save.appendingPathComponent("web-store.json")
        if FileManager.default.fileExists(atPath: file.path) {
            return try JSONDecoder().decode(UUID.self, from: Data(contentsOf: file))
        }
        let id = UUID()
        try AtomicFile.write(JSONEncoder().encode(id), to: file)
        return id
    }
    public static func remove(in save: URL, helper: URL) async throws {
        let file = save.appendingPathComponent("web-store.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let id = try JSONDecoder().decode(UUID.self, from: Data(contentsOf: file))
        let process = Process()
        process.executableURL = helper
        process.arguments = ["--delete-store", id.uuidString]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(15)
        while process.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        if process.isRunning { process.terminate(); throw LibraryFailure("Web 存档清理未完成，存档标识已保留。") }
        guard process.terminationStatus == 0 else { throw LibraryFailure("Web 存档仍在使用或未能清理，请结束应用后重试。") }
    }
    public static func receipt(_ object: [String: Any], to file: URL) throws {
        try AtomicFile.write(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), to: file)
    }

    /// Extract only bounded APK assets. Never resolve archive paths outside this cache.
    public static func assets(apks: [URL], digest: String, save: URL, engine: String) throws -> URL {
        guard (1...32).contains(apks.count), ["Capacitor", "Cordova"].contains(engine) else { throw LibraryFailure("无效的 Web 应用。") }
        let hashes = try apks.map { url -> String in
            let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
            var hash = SHA256()
            while let bytes = try input.read(upToCount: 1 << 20), !bytes.isEmpty { hash.update(data: bytes) }
            return hash.finalize().map { String(format: "%02x", $0) }.joined()
        }
        guard hashes.joined(separator: ":") == digest else { throw LibraryFailure("Web 应用文件已改变，请重新导入。") }
        let cache = save.appendingPathComponent("web-assets"), stamp = cache.appendingPathComponent(".digest")
        let entry = engine == "Capacitor" ? "public/index.html" : "www/index.html"
        if (try? String(contentsOf: stamp, encoding: .utf8)) == digest,
           FileManager.default.fileExists(atPath: cache.appendingPathComponent(entry).path) { return cache }
        let fm = FileManager.default
        if fm.fileExists(atPath: cache.path) { try fm.removeItem(at: cache) }
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        struct Listing: Decodable {
            struct Entry: Decodable { let name: String; let size: UInt64; let method: Int }
            let error: String?; let entries: [Entry]
        }
        var count = 0, bytes: UInt64 = 0
        var names = Set<String>()
        for apk in apks {
            guard let raw = husk_archive_entries(apk.path) else { throw LibraryFailure("无法读取 Web 应用资源。") }
            let data = Data(bytes: raw, count: strlen(raw)); husk_tl_free(raw)
            let listing = try JSONDecoder().decode(Listing.self, from: data)
            guard listing.error == nil else { throw LibraryFailure("Web 应用压缩包损坏。") }
            for item in listing.entries where item.name.hasPrefix("assets/") && !item.name.hasSuffix("/") {
                let name = String(item.name.dropFirst(7))
                guard !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"), !name.contains("\0"),
                      !name.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }),
                      item.size <= 512 << 20, [0, 8].contains(item.method) else { throw LibraryFailure("Web 应用资源路径或大小无效。") }
                guard names.insert(name).inserted else { continue }
                count += 1; bytes += item.size
                guard count <= 50_000, bytes <= 2 << 30 else { throw LibraryFailure("Web 应用资源超过限制。") }
                let target = cache.appendingPathComponent(name)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                var error = [CChar](repeating: 0, count: 512)
                guard husk_archive_extract(apk.path, item.name, target.path, &error, error.count) else { throw LibraryFailure("Web 应用资源提取失败。") }
            }
        }
        guard fm.fileExists(atPath: cache.appendingPathComponent(entry).path) else { throw LibraryFailure("Web 应用缺少首页。") }
        try AtomicFile.write(Data(digest.utf8), to: stamp)
        return cache
    }
}
