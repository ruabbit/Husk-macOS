// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

public struct GameSettings: Codable, Equatable, Sendable {
    public var muted = false
    public var pauseWhenInactive = false
    public init() {}
}

public struct FixtureManifest: Codable, Sendable {
    public let schema: Int
    public let id: String
    public let title: String
    public let abi: Int
    public let library: String
    public let variant: Int
    public let icon: String
}

public struct LibraryGame: Identifiable, Codable, Sendable {
    public let id: String
    public var title: String
    public let importedAt: Date
    public let sourceName: String
    public let apkNames: [String]
    public let digest: String
    public let engine: String?
    public let abis: [String]
    public let fixture: FixtureManifest?
    public var packageName: String? = nil
    public var versionCode: Int? = nil
    public var signerSHA256: [String]? = nil
    public var settings: GameSettings
    public var lastPlayed: Date?
    // Capability belongs to this installed runtime, not to the version which
    // imported the APK. Codable ignores the old persisted unavailableReason.
    public var runtime: String? {
        if fixture != nil { return "orbit" }
        if (1...32).contains(apkNames.count) && engine == "Minecraft" && abis.contains("arm64-v8a") { return "minecraft" }
        return nil
    }
    public var playable: Bool { runtime != nil }
    public var unavailableReason: String? {
        if playable { return nil }
        if !abis.contains("arm64-v8a") { return "此应用没有受支持的 arm64 游戏入口。" }
        return "已完成扫描；此游戏的引擎尚未接入 macOS 原生运行组件。"
    }
}

public struct LibraryIndex: Codable, Sendable {
    public let schema: Int
    public var games: [LibraryGame]
    public init(games: [LibraryGame] = []) { schema = 1; self.games = games }
}

public struct LibraryFailure: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct LibraryPaths: Sendable {
    public let root: URL
    public init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("org.husk.HuskMac", isDirectory: true)
    }
    public var index: URL { root.appendingPathComponent("library.json") }
    public func game(_ id: String) -> URL { root.appendingPathComponent("Games/\(id)", isDirectory: true) }
    public func save(_ id: String) -> URL { root.appendingPathComponent("Saves/\(id)", isDirectory: true) }
    public func checkpoint(_ id: String) -> URL { save(id).appendingPathComponent("checkpoint.json") }
    public var logs: URL { root.appendingPathComponent("Logs", isDirectory: true) }
}
