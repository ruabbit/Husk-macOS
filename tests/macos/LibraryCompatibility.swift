// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import SharedLibrary
import HuskCore

@main struct LibraryCompatibility {
    @MainActor static func main() async {
        let args = CommandLine.arguments
        guard args.count == 4 else { exit(64) }
        let app = URL(fileURLWithPath: args[1]), cases = URL(fileURLWithPath: args[3])
        let paths = LibraryPaths(root: URL(fileURLWithPath: args[2]).appendingPathComponent("Upgrade-\(UUID().uuidString)"))
        let session = SessionController()
        func check(_ value: Bool, _ name: String) throws {
            if !value { throw LibraryFailure(name) }; print("PASS \(name)")
        }
        do {
            let resources = app.appendingPathComponent("Contents/Resources")
            let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: resources.appendingPathComponent("fixture-catalog.json"))) as! [String: Any]
            let repository = try LibraryRepository(paths: paths, trustedFixtureHash: catalog["sha256"] as! String)
            let fixture = try await repository.importGame(resources.appendingPathComponent("Fixtures/OrbitGarden.apk"))
            let unknown = try await repository.importGame(cases.appendingPathComponent("unsupported.apk"))
            try await repository.update(fixture.id, muted: true, pauseWhenInactive: false)
            _ = try await repository.prepare(fixture.id)
            let save = Data("Existing user save must survive capability changes".utf8)
            try save.write(to: paths.checkpoint(fixture.id))
            var legacy = try JSONSerialization.jsonObject(with: Data(contentsOf: paths.index)) as! [String: Any]
            var records = legacy["games"] as! [[String: Any]]
            records[0]["unavailableReason"] = "当前版本支持随附的 Orbit 游戏。"
            // A P3 Minecraft import, with no later migration or reimport.
            var minecraft = records[1]
            minecraft["id"] = String(repeating: "a", count: 64)
            // Retain the historical acceptance sample only as test data.
            minecraft["digest"] = "83468d0acede2cabe3645ff4025a9c190be3cfb90e1864bcbe0277e97967cd95"
            minecraft["engine"] = "Minecraft"; minecraft["abis"] = ["arm64-v8a"]
            minecraft["unavailableReason"] = "当前版本支持随附的 Orbit 游戏。"
            records.append(minecraft)
            var split = minecraft
            split["id"] = String(repeating: "b", count: 64)
            split["digest"] = "split"; split["apkNames"] = ["base.apk", "config.arm64_v8a.apk"]
            split["unavailableReason"] = NSNull(); records.append(split)
            legacy["games"] = records
            let bytes = try JSONSerialization.data(withJSONObject: legacy, options: [.sortedKeys])
            try bytes.write(to: paths.index)
            let reopened = try LibraryRepository(paths: paths, trustedFixtureHash: catalog["sha256"] as! String)
            let games = try await reopened.games()
            try check(games[0].playable && games[0].unavailableReason == nil && games[2].playable,
                      "old-import-reclassified-with-current-runtime")
            try check(games[0].settings.muted && !games[0].settings.pauseWhenInactive &&
                      (try Data(contentsOf: paths.checkpoint(fixture.id))) == save &&
                      (try Data(contentsOf: paths.index)) == bytes, "upgrade-preserves-index-settings-and-save")
            let duplicate = try await reopened.importGame(resources.appendingPathComponent("Fixtures/OrbitGarden.apk"))
            try check(duplicate.playable && duplicate.settings == games[0].settings, "duplicate-import-uses-current-capability")
            try check(!games[1].playable && games[1].unavailableReason != nil && games[3].playable,
                      "unsupported-engine-rejected-and-minecraft-splits-enabled")
            var hashOnly = minecraft
            hashOnly["engine"] = "Unknown"
            let hashOnlyGame = try JSONDecoder().decode(LibraryGame.self, from: JSONSerialization.data(withJSONObject: hashOnly))
            try check(!hashOnlyGame.playable, "sample-hash-cannot-grant-runtime-capability")

            // A stale or forged index cannot grant the helper a different runtime.
            // The actual APK is still the synthetic unsupported case, never guest code.
            records[1]["engine"] = "Minecraft"; records[1]["abis"] = ["arm64-v8a"]
            legacy["games"] = records
            try JSONSerialization.data(withJSONObject: legacy).write(to: paths.index)
            let (candidate, files, checkpoint) = try await reopened.prepare(unknown.id)
            try check(candidate.playable && candidate.unavailableReason == nil,
                      "other-minecraft-builds-use-the-same-runtime")
            try session.start(executable: app.appendingPathComponent("Contents/Helpers/NativeRunner.app/Contents/MacOS/NativeRunner"),
                              game: candidate, apk: files[0], checkpoint: checkpoint, logs: paths.logs, headless: true)
            try await session.wait(until: { !session.active }, timeout: 10)
            try check(session.state == "failed" && session.error?.contains("运行入口") == true,
                      "helper-independently-rejects-false-engine-before-execution")
            try Data("modified APK".utf8).append(to: files[0])
            var refused = false
            do { _ = try await reopened.prepare(unknown.id) } catch { refused = true }
            try check(refused, "launch-still-enforces-import-hash")
            print("Library upgrade: 8 checks passed")
        } catch {
            if session.active { session.stop(); try? await session.wait(until: { !session.active }, timeout: 10) }
            print("FAIL \(error.localizedDescription)"); exit(1)
        }
    }
}

private extension Data {
    func append(to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file); defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: self)
    }
}
