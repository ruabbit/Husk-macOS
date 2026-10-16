// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import SharedLibrary

@main struct JavaSession {
    @MainActor static func main() async {
        let args = CommandLine.arguments
        guard args.count == 4 else { exit(64) }
        let app = URL(fileURLWithPath: args[1]), fixture = URL(fileURLWithPath: args[2])
        let paths = LibraryPaths(root: URL(fileURLWithPath: args[3]).appendingPathComponent("Java-\(UUID().uuidString)"))
        let session = SessionController()
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw LibraryFailure(message) }; print("PASS \(message)")
        }
        do {
            let repository = try LibraryRepository(paths: paths, trustedFixtureHash: "")
            let imported = try await repository.importGame(fixture)
            try check(imported.runtime == "java", "real-dex-import-selects-java")
            try await repository.update(imported.id, muted: true, pauseWhenInactive: false)
            let (game, files, checkpoint) = try await repository.prepare(imported.id)
            let runner = app.appendingPathComponent("Contents/Helpers/NativeRunner.app/Contents/MacOS/NativeRunner")
            try session.start(executable: runner, game: game, apk: files[0], checkpoint: checkpoint,
                              logs: paths.logs, headless: true, automation: true)
            try await session.wait(until: { session.state == "running" || !session.active }, timeout: 40)
            try check(session.state == "running", session.error ?? "packaged-java-first-frame")
            session.send("input", values: ["source":"touch", "phase":0, "x":200, "y":400])
            session.send("input", values: ["source":"touch", "phase":2, "x":200, "y":400])
            session.send("input", values: ["source":"key", "code":0, "down":true])
            session.send("input", values: ["source":"key", "code":0, "down":false])
            session.send("input", values: ["source":"controller", "buttons":1 | (1 << 14), "x":0.25, "y":-0.5,
                "rx":0.75, "ry":-0.25, "lt":0.8, "rt":0.6])
            session.send("input", values: ["source":"controller", "slot":1, "buttons":2])
            try await Task.sleep(nanoseconds: 300_000_000)
            session.send("input", values: ["source":"controller-disconnect", "slot":1])
            try await Task.sleep(nanoseconds: 100_000_000)
            session.send("input", values: ["source":"focus-lost"])
            try await Task.sleep(nanoseconds: 200_000_000)
            try check(session.state == "running", "focus-loss-continues")
            session.togglePause()
            try await session.wait(until: { session.state == "paused" || !session.active }, timeout: 10)
            try check(session.state == "paused", session.error ?? "pause-callback-acknowledged")
            session.send("input", values: ["source":"controller", "buttons":4])
            session.togglePause()
            try await session.wait(until: { session.state == "running" || !session.active }, timeout: 10)
            try check(session.state == "running", "resume-callback-acknowledged")
            session.stop(); try await session.wait(until: { !session.active }, timeout: 35)
            try check(session.state == "exited" && session.error == nil, session.error ?? "storage-close-and-process-reaped")
            try check(session.events.filter { $0["event"] as? String == "storage-closed" }.count == 1, "one-storage-close-receipt")
            let web = session.events.first { $0["event"] as? String == "storage-closed" }?["web"] as? [String: Any] ?? [:]
            let store = try WebStorage.readJavaStore(in: checkpoint.deletingLastPathComponent())
            try check(web["lifecycle"] as? String == "unused" && store.accepts(web), "unused-WebKit-is-explicit-and-bound-to-save")
            let prefs = try String(contentsOf: checkpoint.deletingLastPathComponent().appendingPathComponent("data/shared_prefs/lifecycle.xml"), encoding: .utf8)
            try check(prefs.contains("i destroyed 1") && prefs.contains("i events 63"), "real-input-callbacks-and-final-preferences-persisted")
            try check(prefs.contains("i controller_events 255") && prefs.contains("i controller_held 0"), "real-controller-device-axes-disconnect-focus-and-pause-callbacks")
            print("PASS packaged Java session: \(paths.root.path)")
        } catch {
            if session.active { session.stop(); try? await session.wait(until: { !session.active }, timeout: 35) }
            print("FAIL \(error.localizedDescription); logs: \(paths.logs.path)"); exit(1)
        }
    }
}
