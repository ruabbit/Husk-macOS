// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

public struct GameSettings: Codable, Equatable, Sendable {
    public var muted = false
    public var pauseWhenInactive = false
    public var openFullScreen = false
    public var geode = false
    public init() {}
    private enum CodingKeys: String, CodingKey { case muted, pauseWhenInactive, openFullScreen, geode }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        pauseWhenInactive = try c.decodeIfPresent(Bool.self, forKey: .pauseWhenInactive) ?? false
        openFullScreen = try c.decodeIfPresent(Bool.self, forKey: .openFullScreen) ?? false
        geode = try c.decodeIfPresent(Bool.self, forKey: .geode) ?? false
    }
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

public struct GameExpansion: Codable, Equatable, Sendable {
    public let name: String
    public let size: Int
    public let sha256: String
    static func validName(_ name: String, package: String, version: Int) -> Bool {
        let pieces = name.split(separator: ".", maxSplits: 2)
        guard pieces.count == 3, ["main", "patch"].contains(String(pieces[0])),
              let v = Int(pieces[1]), v > 0, v <= version else { return false }
        return pieces[2] == "\(package).obb" && !name.contains("/") && !name.contains("\\")
    }
}

public struct LibraryGame: Identifiable, Codable, Sendable {
    public let id: String
    public var title: String
    public let importedAt: Date
    public let sourceName: String
    public let apkNames: [String]
    public let digest: String
    public var engine: String?
    public let abis: [String]
    public let fixture: FixtureManifest?
    public var packageName: String? = nil
    public var versionCode: Int? = nil
    public var signerSHA256: [String]? = nil
    public var dexCount: Int? = nil
    public var libraryNames: [String]? = nil
    public var webKind: String? = nil
    public var expansions: [GameExpansion]? = nil
    public var settings: GameSettings
    public var lastPlayed: Date?
    // Capability belongs to this installed runtime, not to the version which
    // imported the APK. Codable ignores the old persisted unavailableReason.
    public var runtime: String? {
        if fixture != nil { return "orbit" }
        guard (1...48).contains(apkNames.count) else { return nil }
        if ["Capacitor", "Cordova"].contains(engine ?? "") { return "web" }
        guard abis.isEmpty || abis.contains("arm64-v8a") else { return nil }
        if abis.isEmpty { return (dexCount ?? 0) > 0 && webKind == nil ? "java" : nil }
        if engine == "Unity 6" { return "java" }
        if ["Python", "Flutter", "libGDX", "Java", "React Native", ".NET / Xamarin"].contains(engine ?? "") { return "java" }
        if engine == nil && (dexCount ?? 0) > 0 { return "java" }
        if engine == "Cocos", let libraries = libraryNames, !libraries.contains("libfmod.so") { return "java" }
        if engine == "SDL", let libraries = libraryNames, !libraries.contains(where: { $0.hasPrefix("libdxvk") }) { return "java" }
        if (1...48).contains(apkNames.count) && abis.contains("arm64-v8a") {
            if engine == "Minecraft" { return "minecraft" }
            if engine == "Cocos" { return "cocos" }
            if engine == "SDL" { return "sdl" }
            if engine == "Godot" { return "godot" }
            if engine == "GameMaker" { return "gamemaker" }
            if engine == "Unreal Engine" { return "ue4" }
            if engine == "Rockstar" { return "gta" }
            if engine == "NativeActivity" { return "nativeactivity" }
            if engine?.hasPrefix("Unity") == true { return "unity" }
        }
        return nil
    }
    public var playable: Bool { runtime != nil }
    public var unavailableReason: String? {
        if playable { return nil }
        if !abis.contains("arm64-v8a") { return "此应用没有受支持的 arm64 游戏入口。" }
        return "已完成扫描；此游戏的引擎尚未接入 macOS 原生运行组件。"
    }

    func verifyExpansions(in directory: URL) throws {
        let entries = expansions ?? []
        guard entries.count <= 2, Set(entries.map { $0.name.split(separator: ".").first }).count == entries.count else {
            throw LibraryFailure("扩展资源清单无效。")
        }
        let folder = directory.appendingPathComponent("obb", isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) {
            let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true,
                  Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)) == Set(entries.map(\.name)) else {
                throw LibraryFailure("扩展资源目录与安装记录不一致。")
            }
        }
        for entry in entries {
            guard GameExpansion.validName(entry.name, package: packageName ?? "", version: versionCode ?? 0) else { throw LibraryFailure("扩展资源名称无效。") }
            let url = folder.appendingPathComponent(entry.name)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, values.fileSize == entry.size,
                  try LibraryRepository.digest(url) == entry.sha256 else { throw LibraryFailure("扩展资源已改变或损坏，请重新导入。") }
        }
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
