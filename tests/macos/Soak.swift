// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import SharedLibrary

@main struct Soak {
    @MainActor static func main() async {
        guard CommandLine.arguments.count == 4, let duration = Double(CommandLine.arguments[3]), duration >= 60 else { exit(64) }
        let app = URL(fileURLWithPath: CommandLine.arguments[1]), out = URL(fileURLWithPath: CommandLine.arguments[2])
        let session = SessionController()
        do {
            let resources = app.appendingPathComponent("Contents/Resources")
            let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: resources.appendingPathComponent("fixture-catalog.json"))) as! [String: Any]
            let paths = LibraryPaths(root: out.appendingPathComponent("Library"))
            let repository = try LibraryRepository(paths: paths, trustedFixtureHash: catalog["sha256"] as! String)
            let imported = try await repository.importGame(resources.appendingPathComponent("Fixtures/OrbitGarden.apk"))
            let (game, apks, save) = try await repository.prepare(imported.id)
            try session.start(executable: app.appendingPathComponent("Contents/Helpers/NativeRunner.app/Contents/MacOS/NativeRunner"),
                              game: game, apk: apks[0], checkpoint: save, logs: paths.logs, headless: true)
            try await session.wait(until: { session.state == "running" || !session.active }, timeout: 20)
            guard session.state == "running" else { throw LibraryFailure(session.error ?? "start failed") }
            let start = Date(); var samples: [[String: Any]] = []; var lastSample = -60.0
            while Date().timeIntervalSince(start) < duration {
                try await Task.sleep(nanoseconds: 500_000_000)
                guard session.active && session.error == nil else { throw LibraryFailure(session.error ?? "unexpected exit") }
                let elapsed = Date().timeIntervalSince(start)
                if elapsed - lastSample >= 60 {
                    let ps = Process(), pipe = Pipe(); ps.executableURL = URL(fileURLWithPath: "/bin/ps")
                    ps.arguments = ["-o", "rss=", "-p", String(session.pid)]; ps.standardOutput = pipe
                    try ps.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); ps.waitUntilExit()
                    let rss = Int(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                    let sample: [String: Any] = ["elapsed": elapsed, "rssKB": rss, "ticks": session.latest["ticks"] ?? 0]
                    samples.append(sample); lastSample = elapsed
                    try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("samples.json"), options: .atomic)
                    print("soak \(Int(elapsed))s rss=\(rss)KB ticks=\(session.latest["ticks"] ?? 0)")
                }
            }
            let elapsed = Date().timeIntervalSince(start)
            session.stop(); try await session.wait(until: { !session.active }, timeout: 5)
            guard session.state == "exited" else { throw LibraryFailure(session.error ?? "stop failed") }
            let result: [String: Any] = ["passed": true, "durationSeconds": elapsed, "samples": samples, "session": session.sessionID ?? "", "headless": true, "muted": true]
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("result.json"))
            print("PASS soak \(elapsed)s; saved and reaped")
        } catch {
            session.stop(); try? await session.wait(until: { !session.active }, timeout: 5)
            print("FAIL soak \(error)"); exit(1)
        }
    }
}
