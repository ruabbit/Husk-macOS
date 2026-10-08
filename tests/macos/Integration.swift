// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import SharedLibrary
import CryptoKit

struct CheckFailure: Error { let message: String }
@main struct Integration {
    @MainActor static func main() async {
        let args = CommandLine.arguments
        guard args.count == 4 else { print("usage: MacIntegrationTests APP OUTPUT CASES"); exit(64) }
        let app = URL(fileURLWithPath: args[1]), results = URL(fileURLWithPath: args[2])
        let cases = URL(fileURLWithPath: args[3])
        let run = results.appendingPathComponent(UUID().uuidString)
        var passed: [String] = []
        let session = SessionController()
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw CheckFailure(message: name) }; passed.append(name); print("PASS \(name)")
        }
        func eventually(_ condition: @escaping @MainActor () -> Bool) async throws { try await session.wait(until: condition, timeout: 20) }
        func event(_ command: String, values: [String: Any] = [:], kind: String) async throws {
            let previous = session.events.last?["seq"] as? Int ?? 0
            session.send(command, values: values)
            try await eventually { session.events.contains { ($0["seq"] as? Int ?? 0) > previous && $0["event"] as? String == kind } }
        }
        func game() -> [String: Any] { session.latest["game"] as? [String: Any] ?? [:] }
        do {
            try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
            let resource = app.appendingPathComponent("Contents/Resources")
            let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: resource.appendingPathComponent("fixture-catalog.json"))) as! [String: Any]
            let hash = catalog["sha256"] as! String
            let paths = LibraryPaths(root: run.appendingPathComponent("Library"))
            let repository = try LibraryRepository(paths: paths, trustedFixtureHash: hash)
            let first = try await repository.importGame(resource.appendingPathComponent("Fixtures/OrbitGarden.apk"))
            let second = try await repository.importGame(resource.appendingPathComponent("Fixtures/OrbitGardenDusk.apk"))
            try check(first.playable && second.playable && first.id != second.id, "import-two-playable-fixtures")
            try check(FileManager.default.fileExists(atPath: paths.game(first.id).appendingPathComponent("icon.data").path), "import-preserves-icon")
            let duplicate = try await repository.importGame(cases.appendingPathComponent("compressed.xapk"))
            let deduplicated = try await repository.games()
            try check(duplicate.id == first.id && deduplicated.count == 2, "compressed-bundle-and-deduplication")
            for name in ["damaged.apk", "duplicate.apks"] {
                var rejected = false
                do { _ = try await repository.importGame(cases.appendingPathComponent(name)) } catch { rejected = true }
                try check(rejected, "reject-\(name)")
            }
            let unknown = try await repository.importGame(cases.appendingPathComponent("unsupported.apk"))
            try check(!unknown.playable && unknown.unavailableReason != nil, "unsupported-import-has-clear-status")
            let forged = try await repository.importGame(cases.appendingPathComponent("forged.apk"))
            try check(!forged.playable, "forged-fixture-cannot-execute")
            var settings = GameSettings(); settings.muted = true; settings.pauseWhenInactive = false
            try await repository.update(first.id, settings: settings)
            let reopened = try LibraryRepository(paths: paths, trustedFixtureHash: hash)
            let reopenedGames = try await reopened.games()
            try check(reopenedGames.count == 4 && reopenedGames.first(where: { $0.id == first.id })?.settings == settings, "restart-preserves-library-and-settings")
            async let muteUpdate: Void = repository.update(first.id, muted: false)
            async let focusUpdate: Void = repository.update(first.id, pauseWhenInactive: true)
            _ = try await (muteUpdate, focusUpdate)
            let merged = try await reopened.games().first(where: { $0.id == first.id })?.settings
            try check(merged == GameSettings(), "independent-setting-updates-preserve-both-fields")
            try await repository.update(first.id, settings: settings)
            let brokenPaths = LibraryPaths(root: run.appendingPathComponent("BrokenLibrary"))
            let broken = try LibraryRepository(paths: brokenPaths, trustedFixtureHash: hash)
            let badIndex = Data("not-json".utf8); try badIndex.write(to: brokenPaths.index)
            var rejectedIndex = false
            do { _ = try await broken.games() } catch { rejectedIndex = true }
            try check(rejectedIndex && (try Data(contentsOf: brokenPaths.index)) == badIndex, "corrupt-library-is-preserved")

            let executable = app.appendingPathComponent("Contents/Helpers/NativeRunner.app/Contents/MacOS/NativeRunner")
            func start(_ id: String, label: String, window: Bool = false) async throws {
                let (entry, files, save) = try await repository.prepare(id)
                try session.start(executable: executable, game: entry, apk: files[0], checkpoint: save, logs: paths.logs,
                                  headless: true, automation: true, diagnostics: run.appendingPathComponent(label), hiddenWindow: window)
                try await eventually { session.state == "running" || !session.active }
                guard session.state == "running" else { throw CheckFailure(message: "runner-start: \(session.error ?? "unknown")") }
                try await event("status", kind: "status")
            }
            func stop() async throws {
                session.stop(); try await eventually { !session.active }
                guard session.state == "exited" else { throw CheckFailure(message: "runner-stop: \(session.error ?? "unknown")") }
            }
            try await start(first.id, label: "FirstPlay")
            try check(session.latest["headless"] as? Bool == true && session.latest["windowVisible"] as? Bool == false, "no-window-created")
            try await event("capture", values: ["name": "initial.png"], kind: "capture")
            try await event("input", values: ["source": "key", "code": 124, "down": true], kind: "input")
            try await event("step", values: ["frames": 8], kind: "status")
            try check((game()["x"] as? Double ?? 0) == 352, "keyboard-moves-guest-player")
            try await event("pause", kind: "state")
            let pausedTicks = session.latest["ticks"] as? Int
            try await event("step", values: ["frames": 40], kind: "status")
            try check(session.latest["ticks"] as? Int == pausedTicks, "pause-stops-guest-simulation")
            try await event("capture", values: ["name": "paused.png"], kind: "capture")
            try await event("resume", kind: "state")
            try await event("step", values: ["frames": 8], kind: "status")
            try check((game()["x"] as? Double ?? 0) == 352, "pause-clears-held-key")
            try await event("input", values: ["source": "controller", "x": -1, "y": 0], kind: "input")
            try await event("step", values: ["frames": 8], kind: "status")
            try check((game()["x"] as? Double ?? 0) == 320, "controller-path-moves-guest-player")
            try await event("input", values: ["source": "focus-lost"], kind: "input")
            try await event("step", values: ["frames": 8], kind: "status")
            try check((game()["x"] as? Double ?? 0) == 320, "focus-loss-clears-controller-state")
            for point in [[110,105],[250,85],[390,105],[530,85],[530,320],[390,300],[250,320],[110,300]] {
                try await event("input", values: ["source": "pointer", "x": point[0], "y": point[1], "down": true], kind: "input")
                try await event("step", values: ["frames": 180], kind: "status")
            }
            let won = game()
            try check(won["collected"] as? Int == 255 && won["wins"] as? Int == 1, "pointer-play-reaches-game-objective")
            try check((session.latest["audioNonzero"] as? Int ?? 0) > 1000, "guest-produces-nonzero-PCM")
            try await event("capture", values: ["name": "won.png"], kind: "capture")
            try await stop()
            let saved = try Data(contentsOf: paths.checkpoint(first.id))
            try check(saved.count > 0 && session.events.last?["state"] as? String == "exited", "checkpoint-ack-before-reaped-exit")
            try check(try Data(contentsOf: run.appendingPathComponent("FirstPlay/initial.png")) != Data(contentsOf: run.appendingPathComponent("FirstPlay/won.png")), "ANGLE-renders-different-game-states")
            try await repository.remove(first.id)
            try check(!FileManager.default.fileExists(atPath: paths.game(first.id).path) && (try Data(contentsOf: paths.checkpoint(first.id))) == saved, "remove-game-preserves-save")
            _ = try await repository.importGame(resource.appendingPathComponent("Fixtures/OrbitGarden.apk"))
            try await start(first.id, label: "Restored")
            try check(game()["collected"] as? Int == 255 && game()["wins"] as? Int == 1, "reimport-and-restart-restores-game-progress")
            try await stop()
            try await start(second.id, label: "SecondGame")
            try check(game()["variant"] as? Int == 1 && game()["wins"] as? Int == 0, "switch-game-uses-fresh-process-and-save")
            try await event("capture", values: ["name": "dusk.png"], kind: "capture")
            try await stop()
            let previousSave = try Data(contentsOf: paths.checkpoint(second.id))
            try await start(second.id, label: "UnexpectedExit")
            session.send("exit-unexpectedly")
            try await eventually { !session.active }
            let survivingLibrary = try await repository.games()
            try check(session.state == "failed" && session.error != nil && survivingLibrary.count == 4,
                      "unexpected-child-exit-isolated-from-library")
            try check(try Data(contentsOf: paths.checkpoint(second.id)) == previousSave, "unexpected-exit-preserves-last-save")
            try await start(first.id, label: "Recovery")
            try await stop()
            try check(session.state == "exited", "new-session-works-after-child-failure")
            try await start(first.id, label: "NativeWindow", window: true)
            try check(session.latest["headless"] as? Bool == false && session.latest["windowVisible"] as? Bool == false, "AppKit-window-host-stays-hidden")
            try await event("capture", values: ["name": "window-surface.png"], kind: "capture")
            try check(session.latest["saved"] as? Bool == true, "ANGLE-CAMetalLayer-window-surface-renders")
            try await stop()
            try await repository.deleteSave(second.id)
            try check(!FileManager.default.fileExists(atPath: paths.checkpoint(second.id).path), "explicit-save-deletion")
            let corrupt = Data("broken-save".utf8)
            _ = try await repository.prepare(second.id)
            try corrupt.write(to: paths.checkpoint(second.id))
            var saveRejected = false
            do { try await start(second.id, label: "CorruptSave") } catch { saveRejected = true }
            try check(saveRejected && (try Data(contentsOf: paths.checkpoint(second.id))) == corrupt, "corrupt-save-is-rejected-without-overwrite")
            try await repository.deleteSave(second.id)
            try FileManager.default.createDirectory(at: paths.checkpoint(second.id), withIntermediateDirectories: true)
            var unreadableRejected = false
            do { try await start(second.id, label: "UnreadableSave") } catch { unreadableRejected = true }
            try check(unreadableRejected && session.events.last?["state"] as? String == "failed"
                      && FileManager.default.fileExists(atPath: paths.checkpoint(second.id).path),
                      "unreadable-save-reports-failure-without-crashing")
            let summary: [String: Any] = ["passed": passed, "count": passed.count, "run": run.path,
                "modes": ["headless", "hidden-AppKit-window"], "visibleWindows": false,
                "speakerOutput": false, "physicalController": false, "deliberateCrash": false]
            try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]).write(to: results.appendingPathComponent("latest.json"))
            print("PASS \(passed.count) checks; evidence: \(run.path)")
        } catch {
            session.stop()
            try? await session.wait(until: { !session.active }, timeout: 4)
            print("FAIL \(error); \(session.error ?? ""); evidence: \(run.path)")
            exit(1)
        }
    }
}
