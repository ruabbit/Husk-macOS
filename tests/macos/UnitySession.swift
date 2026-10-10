// SPDX-License-Identifier: GPL-2.0-or-later
// Explicit real-game opt-in: read existing APKs, write only disposable test data.
import Foundation
import SharedLibrary
import Darwin

@main struct UnitySession {
    @MainActor static func main() async {
        let args = CommandLine.arguments
        guard args.count == 7, args[5] == "--seconds", let seconds = Double(args[6]), seconds > 0, seconds <= 120 else {
            print("usage: MacUnitySession APP LIBRARY_ROOT GAME_ID OUTPUT --seconds 20"); exit(64)
        }
        let app = URL(fileURLWithPath: args[1]), source = LibraryPaths(root: URL(fileURLWithPath: args[2]))
        let output = URL(fileURLWithPath: args[4]), fm = FileManager.default, session = SessionController()
        var failure: String?, checks = [String]()
        do {
            let index = try JSONDecoder().decode(LibraryIndex.self, from: Data(contentsOf: source.index))
            guard var game = index.games.first(where: { $0.id == args[3] }), game.runtime == "unity" else { throw LibraryFailure("Unity game not found") }
            // Refuse a destination within the real library, including symlinks.
            let resolved = output.resolvingSymlinksInPath().path
            guard !resolved.hasPrefix(source.root.resolvingSymlinksInPath().path + "/"), resolved != source.root.resolvingSymlinksInPath().path else { throw LibraryFailure("Use a disposable test output outside the user library") }
            try fm.createDirectory(at: output, withIntermediateDirectories: true)
            game.settings.muted = true; game.settings.pauseWhenInactive = false
            let checkpoint = output.appendingPathComponent("checkpoint.json")
            try session.start(executable: app.appendingPathComponent("Contents/Helpers/NativeRunner.app/Contents/MacOS/NativeRunner"),
                              game: game, apk: source.game(game.id).appendingPathComponent(game.apkNames[0]),
                              checkpoint: checkpoint, logs: output.appendingPathComponent("Logs"), headless: true,
                              automation: true, diagnostics: output)
            try await session.wait(until: { session.state == "running" || !session.active }, timeout: 95)
            guard session.state == "running" else { throw LibraryFailure(session.error ?? "No first frame") }
            checks.append("real-apk-first-render")
            let control = output.appendingPathComponent("control.jsonl")
            try Data().write(to: control)
            var consumed = 0
            let deadline = Date().addingTimeInterval(seconds)
            while session.active && Date() < deadline {
                let data = try Data(contentsOf: control)
                if data.count > consumed, let end = data[consumed...].lastIndex(of: 10) {
                    for line in data[consumed...end].split(separator: 10) {
                        if let object = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                           let command = object["command"] as? String {
                            session.send(command, values: object)
                        }
                    }
                    consumed = end + 1
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard session.state == "running" else { throw LibraryFailure(session.error ?? "Game stopped") }
            session.send("capture", values: ["name": "frame.png"])
            try await session.wait(until: { session.events.contains { $0["event"] as? String == "capture" && $0["name"] as? String == "frame.png" } || !session.active }, timeout: 5)
            guard session.events.contains(where: { $0["event"] as? String == "capture" && $0["name"] as? String == "frame.png" && $0["saved"] as? Bool == true }) else { throw LibraryFailure("No captured EGL frame") }
            checks.append("captured-egl-frame")
            session.send("input", values: ["source": "focus-lost"])
            try await Task.sleep(nanoseconds: 300_000_000)
            guard session.state == "running" else { throw LibraryFailure("Focus loss paused the game") }
            checks.append("inactive-continues")
            session.togglePause()
            try await session.wait(until: { session.state == "paused" || !session.active }, timeout: 18)
            guard session.state == "paused" else { throw LibraryFailure(session.error ?? "No pause acknowledgement") }
            checks.append("native-pause-acknowledged")
            session.togglePause()
            try await session.wait(until: { session.state == "running" || !session.active }, timeout: 18)
            guard session.state == "running" else { throw LibraryFailure(session.error ?? "No resume acknowledgement") }
            checks.append("native-resume-acknowledged")
            session.stop(); try await session.wait(until: { !session.active }, timeout: 35)
            guard session.state == "exited" else { throw LibraryFailure(session.error ?? "No completed destruction") }
            checks.append("storage-closed-and-process-reaped")
        } catch {
            failure = error.localizedDescription
            if session.active { session.stop(); try? await session.wait(until: { !session.active }, timeout: 35) }
        }
        let result: [String: Any] = ["checks": checks, "state": session.state, "error": failure ?? session.error as Any? ?? NSNull(), "events": session.events]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: output.appendingPathComponent("result.json"))
        }
        print("Unity session: \(session.state), checks=\(checks.count), error=\(failure ?? session.error ?? "none")")
        exit(failure == nil && session.error == nil ? 0 : 1)
    }
}
