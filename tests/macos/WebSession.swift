// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import SharedLibrary

@main struct WebSession {
    @MainActor static func main() async {
        let args = CommandLine.arguments
        guard args.count == 5 else { exit(64) }
        let app = URL(fileURLWithPath: args[1]), fixture = URL(fileURLWithPath: args[2]), kind = args[3]
        let paths = LibraryPaths(root: URL(fileURLWithPath: args[4]).appendingPathComponent("Web-\(UUID().uuidString)"))
        let session = SessionController(), helper = WebStorage.helper(in: app)
        func check(_ passed: Bool, _ why: String) throws { if !passed { throw LibraryFailure(why) }; print("PASS \(why)") }
        func evaluate(_ script: String) async throws -> Any {
            let request = UUID().uuidString
            session.send("evaluate", values: ["script": script, "request": request])
            try await session.wait(until: { session.events.contains { $0["request"] as? String == request } || !session.active }, timeout: 10)
            guard let event = session.events.first(where: { $0["request"] as? String == request }), event["error"] as? String == "" else {
                throw LibraryFailure("Web evaluation failed: \(session.events.last ?? [:])")
            }
            return event["value"] ?? NSNull()
        }
        func javascriptAsync(_ script: String) async throws -> Any {
            _ = try await evaluate("window.testResult=null; window.testError=null; (async()=>{\(script)})().then(v=>window.testResult=JSON.stringify(v)).catch(e=>window.testError=String(e)); true")
            for _ in 0..<100 {
                let result = try await evaluate("({result:window.testResult,error:window.testError})") as? [String: Any] ?? [:]
                if let error = result["error"] as? String { throw LibraryFailure(error) }
                if let json = result["result"] as? String { return try JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed]) }
                try await Task.sleep(for: .milliseconds(50))
            }
            throw LibraryFailure("Web async operation timed out")
        }
        do {
            let repository = try LibraryRepository(paths: paths, trustedFixtureHash: "")
            let imported = try await repository.importGame(fixture)
            try check(imported.runtime == "web", "\(kind) import selects WebRunner")
            func start() async throws {
                let (game, files, checkpoint) = try await repository.prepare(imported.id)
                try session.start(executable: helper, game: game, apk: files[0], checkpoint: checkpoint, logs: paths.logs, headless: true, automation: true)
                try await session.wait(until: { session.state == "running" || !session.active }, timeout: 25)
                try check(session.state == "running", session.error ?? "web document loaded")
                let ready = try await evaluate("window.fixtureReady === true")
                try check(ready as? Bool == true, "real WebKit loaded extracted APK assets")
            }
            func stop() async throws {
                session.stop(); try await session.wait(until: { !session.active }, timeout: 35)
                try check(session.state == "exited" && session.error == nil, session.error ?? "web document detached and child reaped")
                try check(session.events.filter { $0["event"] as? String == "web-storage-detached" }.count == 1 &&
                          !session.events.contains { $0["event"] as? String == "storage-closed" }, "explicit WebKit ownership receipt")
            }
            try await start()
            _ = try await javascriptAsync("return await persist('retained');")
            if kind == "capacitor" {
                _ = try await evaluate("androidBridge.postMessage(JSON.stringify({pluginId:'App',methodName:'getInfo',callbackId:'info',options:{}})); true")
                try await Task.sleep(for: .milliseconds(100))
                let info = try await evaluate("responses.some(x=>x.callbackId==='info' && x.success && x.data.id==='org.husk.driver')")
                try check(info as? Bool == true, "shared Capacitor native plugin round trip")
            }
            _ = try await evaluate("window.ticks=0; window.tickTimer=setInterval(()=>window.ticks++,10); true")
            // Hidden WebKit pages throttle timers; first observe a real tick,
            // rather than assuming a foreground 10 ms scheduling interval.
            for _ in 0..<60 {
                if (try await evaluate("window.ticks") as? Int ?? 0) > 0 { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            let initialTicks = try await evaluate("window.ticks") as? Int ?? 0
            try check(initialTicks > 0, "Web timer was running before pause")
            session.togglePause(); try await session.wait(until: { session.state == "paused" || !session.active }, timeout: 10)
            try check(session.state == "paused", "web pause acknowledged")
            let pausedTicks = try await evaluate("window.ticks") as? Int
            try await Task.sleep(for: .milliseconds(1200))
            let laterTicks = try await evaluate("window.ticks") as? Int
            try check(pausedTicks != nil && pausedTicks == laterTicks, "Web timer callbacks stop while paused")
            session.togglePause(); try await session.wait(until: { session.state == "running" || !session.active }, timeout: 10)
            try check(session.state == "running", "web resume acknowledged")
            var resumedTicks = -1
            for _ in 0..<60 {
                resumedTicks = try await evaluate("window.ticks") as? Int ?? -1
                if resumedTicks > (pausedTicks ?? 0) { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            try check(resumedTicks > (pausedTicks ?? 0), "Web timer callbacks resume")
            _ = try await evaluate("clearInterval(window.tickTimer); true")
            try await stop(); try await start()
            let saved = try await javascriptAsync("return await readSave();") as? [String: Any] ?? [:]
            try check(saved["local"] as? String == "retained" && saved["indexed"] as? String == "retained", "localStorage and IndexedDB survive process exit and reopen")
            print("Cookie behavior for local scheme: \(saved["cookie"] ?? "")")
            try await stop()
            let id = try WebStorage.identifier(in: paths.save(imported.id))
            try await repository.deleteSave(imported.id, webHelper: helper)
            try await start()
            let replacement = try WebStorage.identifier(in: paths.save(imported.id))
            try check(replacement != id, "clear save creates a fresh WebKit store")
            let empty = try await javascriptAsync("return await readSave();") as? [String: Any] ?? [:]
            try check(empty["local"] is NSNull && empty["indexed"] is NSNull, "deleted web state does not reappear")
            try await stop(); try await repository.deleteSave(imported.id, webHelper: helper)
            print("PASS \(kind) packaged WebKit persistence and cleanup")
        } catch {
            if session.active { session.stop(); try? await session.wait(until: { !session.active }, timeout: 35) }
            print("FAIL \(error.localizedDescription); logs: \(paths.logs.path)"); exit(1)
        }
    }
}
