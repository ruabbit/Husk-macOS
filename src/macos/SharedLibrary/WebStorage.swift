// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import CryptoKit
import HuskCore

/// WebKit owns its database files. Saves contains the stable, private store ID;
/// removal must run in WebRunner, whose bundle owns that WebKit data directory.
public enum WebStorage {
    public struct JavaStore: Codable, Equatable, Sendable {
        public let id: UUID
        public let legacyPackage: String?
        public func accepts(_ receipt: [String: Any]) -> Bool {
            guard receipt["store"] as? String == id.uuidString else { return false }
            let lifecycle = receipt["lifecycle"] as? String, storage = receipt["storage"] as? String
            return (lifecycle == "detached" && storage == "webkit-managed") || (lifecycle == "unused" && storage == "unused")
        }
    }
    public static func javaHelper(in app: URL) -> URL {
        app.appendingPathComponent("Contents/Helpers/NativeRunner.app/Contents/MacOS/NativeRunner")
    }
    public static func readJavaStore(in save: URL) throws -> JavaStore {
        try JSONDecoder().decode(JavaStore.self, from: Data(contentsOf: save.appendingPathComponent("java-web-store.json")))
    }
    public static func javaStore(in save: URL, package: String) throws -> JavaStore {
        let file = save.appendingPathComponent("java-web-store.json")
        if FileManager.default.fileExists(atPath: file.path) { return try readJavaStore(in: save) }
        // Pre-build-8 saves used a package-wide WebKit UUID. Keep that binding:
        // changing it would strand existing website data. Fresh saves get an
        // independent identity even when another library has the same package.
        let legacy = FileManager.default.fileExists(atPath: save.appendingPathComponent("data").path)
        var id = UUID()
        if legacy {
            var h1: UInt64 = 1469598103934665603, h2: UInt64 = 1099511628211 ^ 0x9e3779b97f4a7c15
            for byte in package.utf8 { h1 = (h1 ^ UInt64(byte)) &* 1099511628211; h2 = ((h2 ^ UInt64(byte)) &* 0x100000001b3) &+ 7 }
            var bytes = (0..<8).map { UInt8(truncatingIfNeeded: h1 >> ($0 * 8)) } + (0..<8).map { UInt8(truncatingIfNeeded: h2 >> ($0 * 8)) }
            bytes[6] = (bytes[6] & 0x0f) | 0x40; bytes[8] = (bytes[8] & 0x3f) | 0x80
            id = UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
        }
        let store = JavaStore(id: id, legacyPackage: legacy ? package : nil)
        try AtomicFile.write(JSONEncoder().encode(store), to: file)
        return store
    }
    public static func removeJava(in save: URL, helper: URL) async throws {
        guard FileManager.default.fileExists(atPath: save.appendingPathComponent("java-web-store.json").path) else { return }
        let store = try readJavaStore(in: save)
        // A legacy package store may still belong to another library/save.
        // Clearing this save drops its binding; its next launch gets a new UUID.
        // Never delete shared legacy bytes on behalf of just one save.
        guard store.legacyPackage == nil else { return }
        try await removeStore(store.id, helper: helper, option: "--delete-web-store")
    }
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
        try await removeStore(id, helper: helper, option: "--delete-store")
    }
    private static func removeStore(_ id: UUID, helper: URL, option: String) async throws {
        let process = Process()
        process.executableURL = helper
        process.arguments = [option, id.uuidString]
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
        guard (1...48).contains(apks.count), ["Capacitor", "Cordova"].contains(engine) else { throw LibraryFailure("无效的 Web 应用。") }
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
