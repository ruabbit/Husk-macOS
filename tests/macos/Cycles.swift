// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Darwin
import SharedLibrary

@main struct Cycles {
    @MainActor static func main() async {
        guard CommandLine.arguments.count == 4, let cycles = Int(CommandLine.arguments[3]), (1...100).contains(cycles) else { exit(64) }
        let app = URL(fileURLWithPath: CommandLine.arguments[1]), output = URL(fileURLWithPath: CommandLine.arguments[2])
        let session = SessionController()
        do {
            let resources = app.appendingPathComponent("Contents/Resources")
            let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: resources.appendingPathComponent("fixture-catalog.json"))) as! [String: Any]
            let paths = LibraryPaths(root: output.appendingPathComponent("Library"))
            let repository = try LibraryRepository(paths: paths, trustedFixtureHash: catalog["sha256"] as! String)
            var games: [LibraryGame] = []
            for name in ["OrbitGarden", "OrbitGardenDusk"] { games.append(try await repository.importGame(resources.appendingPathComponent("Fixtures/\(name).apk"))) }
            var records: [[String: Any]] = []
            for cycle in 0..<cycles {
                let (game, apks, checkpoint) = try await repository.prepare(games[cycle % 2].id)
                try session.start(executable: app.appendingPathComponent("Contents/Helpers/NativeRunner.app/Contents/MacOS/NativeRunner"),
                                  game: game, apk: apks[0], checkpoint: checkpoint, logs: paths.logs, headless: true, automation: true)
                try await session.wait(until: { session.state == "running" || !session.active }, timeout: 20)
                guard session.state == "running" else { throw LibraryFailure(session.error ?? "launch failed") }
                session.send("step", values: ["frames": 60])
                try await session.wait(until: { (session.latest["ticks"] as? Int ?? 0) >= 60 || !session.active })
                let pid = session.pid, id = session.sessionID!
                session.stop(); try await session.wait(until: { !session.active }, timeout: 5)
                guard session.state == "exited", kill(pid, 0) == -1, errno == ESRCH else { throw LibraryFailure("Runner not saved/reaped at cycle \(cycle)") }
                records.append(["cycle": cycle + 1, "pid": pid, "session": id, "game": game.id, "reaped": true])
            }
            let result: [String: Any] = ["passed": true, "cycles": cycles, "visibleWindows": false, "records": records]
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("result.json"))
            print("PASS \(cycles) headless start/play/save/reap cycles, alternating games")
        } catch {
            session.stop(); try? await session.wait(until: { !session.active }, timeout: 5)
            print("FAIL cycles: \(error)"); exit(1)
        }
    }
}
