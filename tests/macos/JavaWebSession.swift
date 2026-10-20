// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import SharedLibrary

@main struct JavaWebSession {
    @MainActor static func main() async {
        let args = CommandLine.arguments
        guard args.count == 5 else { exit(64) }
        let app = URL(fileURLWithPath: args[1]), fixture = URL(fileURLWithPath: args[2]), scenario = args[4]
        let root = URL(fileURLWithPath: args[3]).appendingPathComponent("JavaWeb-\(UUID().uuidString)")
        let paths = LibraryPaths(root: root), otherPaths = LibraryPaths(root: root.appendingPathComponent("second-library"))
        let helper = WebStorage.javaHelper(in: app), session = SessionController()
        func check(_ passed: Bool, _ why: String) throws { if !passed { throw LibraryFailure(why) }; print("PASS \(why)") }
        func storeExists(_ id: UUID) async throws -> Bool {
            let process = Process(); process.executableURL = helper
            process.arguments = ["--has-web-store", id.uuidString]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run()
            let deadline = Date().addingTimeInterval(15)
            while process.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(30)) }
            if process.isRunning { process.terminate(); throw LibraryFailure("Store query timed out") }
            guard [0, 3].contains(process.terminationStatus) else { throw LibraryFailure("Store query failed") }
            return process.terminationStatus == 0
        }
        func evaluate(_ script: String, optional: Bool = false) async throws -> Any {
            let request = UUID().uuidString
            session.send("evaluate", values: ["script": script, "request": request])
            try await session.wait(until: { session.events.contains { $0["request"] as? String == request } || !session.active }, timeout: 10)
            guard let event = session.events.first(where: { $0["request"] as? String == request }) else { throw LibraryFailure(session.error ?? "No WebView evaluation") }
            if event["error"] as? String != "" {
                if optional { return NSNull() }
                throw LibraryFailure("WebView evaluation: \(event["error"] ?? "unknown")")
            }
            return event["value"] ?? NSNull()
        }
        func javascriptAsync(_ script: String) async throws -> Any {
            _ = try await evaluate("window.testResult=null;window.testError=null;(async()=>{\(script)})().then(v=>window.testResult=JSON.stringify(v)).catch(e=>window.testError=String(e));true")
            for _ in 0..<100 {
                let result = try await evaluate("({result:window.testResult,error:window.testError})") as? [String: Any] ?? [:]
                if let error = result["error"] as? String { throw LibraryFailure(error) }
                if let json = result["result"] as? String { return try JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed]) }
                try await Task.sleep(for: .milliseconds(40))
            }
            throw LibraryFailure("Java WebView async script timed out")
        }
        func preferences(_ save: URL) -> String {
            (try? String(contentsOf: save.appendingPathComponent("data/shared_prefs/web.xml"), encoding: .utf8)) ?? ""
        }
        do {
            let repository = try LibraryRepository(paths: paths, trustedFixtureHash: "")
            let imported = try await repository.importGame(fixture)
            let otherRepository = try LibraryRepository(paths: otherPaths, trustedFixtureHash: "")
            let other = try await otherRepository.importGame(fixture)
            let save = paths.save(imported.id), otherSave = otherPaths.save(other.id)
            try check(imported.runtime == "java", "real DEX routes through NativeRunner Java profile")
            func start(_ repository: LibraryRepository, _ game: LibraryGame, _ paths: LibraryPaths) async throws {
                let (current, files, checkpoint) = try await repository.prepare(game.id)
                try session.start(executable: helper, game: current, apk: files[0], checkpoint: checkpoint, logs: paths.logs, headless: true, automation: true)
                try await session.wait(until: { session.state == "running" || !session.active }, timeout: 35)
                try check(session.state == "running", session.error ?? "Java first frame")
                var ready = false
                for _ in 0..<120 {
                    if try await evaluate("window.fixtureReady===true", optional: true) as? Bool == true { ready = true; break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                try check(ready, "real Java WebView loaded APK assets")
            }
            func stop(success: Bool = true) async throws {
                session.stop(); try await session.wait(until: { !session.active }, timeout: 35)
                let receipts = session.events.filter { $0["event"] as? String == "storage-closed" }
                if success {
                    try check(session.state == "exited" && session.error == nil, session.error ?? "Android destroyed, WebKit detached, child reaped")
                    let web = receipts.first?["web"] as? [String: Any]
                    try check(receipts.count == 1 && web?["lifecycle"] as? String == "detached" && web?["storage"] as? String == "webkit-managed" && web?["saveStage"] as? String == "prepared", "one composite receipt retains native, save-stage and WebKit ownership")
                } else { try check(session.state == "failed" && session.error != nil, "incomplete or mismatched shutdown rejected") }
            }
            if scenario == "legacy" {
                _ = try await repository.prepare(imported.id)
                try FileManager.default.createDirectory(at: save.appendingPathComponent("data"), withIntermediateDirectories: true)
            }
            try await start(repository, imported, paths)
            let identity = try WebStorage.readJavaStore(in: save)
            _ = try await javascriptAsync("return await persist('retained');")
            if scenario == "save-bridge" || scenario == "save-paused" {
                try check(try await evaluate("typeof nativeSave.store==='function'") as? Bool == true, "real JavaScript interface is installed")
                _ = try await evaluate("window.addEventListener('pagehide',e=>{nativeSave.store();e.waitUntil(new Promise(resolve=>setTimeout(resolve,20)).then(()=>persist('from-save-stage')).then(()=>nativeSave.store()));});true")
                if scenario == "save-paused" {
                    session.togglePause()
                    try await session.wait(until: { session.state == "paused" || !session.active }, timeout: 10)
                    try check(session.state == "paused", "Android activity paused before host save stage")
                }
                try await stop()
                try check(preferences(save).contains("i bridge_calls 2") && preferences(save).contains("i main_at_destroy 2"), "pagehide plugin and explicit async save finished before Android destroy")
                try check(session.events.contains { $0["event"] as? String == "web-save-stage" && $0["prepared"] as? Bool == true }, "host acknowledged the completed save stage")
                try await start(repository, imported, paths)
                try check(try await evaluate("nativeSave.previous()") as? Int == 2, "real Java plugin preferences survive process reopen")
                let restored = try await javascriptAsync("return await readSave();") as? [String: Any] ?? [:]
                try check(restored["local"] as? String == "from-save-stage" && restored["indexed"] as? String == "from-save-stage", "explicit asynchronous Web save survives process reopen")
                try check(try await evaluate("localStorage.getItem('pagehideCount')==='1' && localStorage.getItem('unloadCount')==='1'") as? Bool == true, "pagehide and unload delivered exactly once")
                try await stop()
            } else if scenario == "late-bridge" {
                _ = try await evaluate("nativeSave.armLateDestroy();true")
                try await stop(success: false)
                try check(session.events.contains { $0["event"] as? String == "native-lifecycle" && $0["lifecycle"] as? String == "destroyed" }, "Android destruction finished despite rejected late plugin call")
                try check(!session.events.contains { $0["event"] as? String == "storage-closed" }, "Java calls after the save stage still reject the composite receipt")
            } else if ["save-rejected", "save-promise-rejected", "save-timeout", "save-script-failed"].contains(scenario) {
                let handler = scenario == "save-rejected" ? "try { nativeSave.fail(); } catch(e) {}" : scenario == "save-promise-rejected" ? "e.waitUntil(Promise.reject(new Error('Expected asynchronous save failure')));" : scenario == "save-timeout" ? "e.waitUntil(new Promise(()=>{}));" : "throw new Error('Expected save handler failure');"
                _ = try await evaluate("window.addEventListener('pagehide',e=>{\(handler)});true")
                try await stop(success: false)
                try check(session.events.contains { $0["event"] as? String == "native-lifecycle" && $0["lifecycle"] as? String == "destroyed" }, "Android destruction succeeded independently of rejected Web bridge")
                try check(!session.events.contains { $0["event"] as? String == "storage-closed" }, "rejected or timed out save cannot become a successful receipt")
                try check(session.events.contains { $0["event"] as? String == "web-save-stage" && $0["prepared"] as? Bool == false }, "failed save stage is explicit")
            } else if scenario == "child-save" {
                _ = try await javascriptAsync("const frame=document.createElement('iframe');const loaded=new Promise(resolve=>frame.onload=resolve);frame.src='storage.html';document.body.appendChild(frame);await loaded;frame.contentWindow.addEventListener('pagehide',()=>frame.contentWindow.nativeSave.store());return true;")
                try await stop()
                try check(preferences(save).contains("i bridge_calls 1") && preferences(save).contains("i main_at_destroy 1"), "same-origin child frame saved through its real Java bridge")
            } else if scenario == "cross-origin-save" {
                _ = try await javascriptAsync("const frame=document.createElement('iframe');frame.sandbox='allow-scripts';const loaded=new Promise(resolve=>frame.onload=resolve);frame.srcdoc='<p>isolated frame</p>';document.body.appendChild(frame);await loaded;return true;")
                try await stop(success: false)
                try check(!session.events.contains { $0["event"] as? String == "storage-closed" }, "unprepared cross-origin frame cannot be reported saved")
            } else if scenario == "destroy-failed" {
                session.send("input", values: ["source": "key", "code": 3, "down": true])
                try await session.wait(until: { preferences(save).contains("b fail_destroy true") || !session.active }, timeout: 5)
                try check(preferences(save).contains("b fail_destroy true"), "Java destroy failure armed via real key callback")
                try await stop(success: false)
                try check(!session.events.contains { $0["event"] as? String == "storage-closed" }, "Web teardown cannot override failed Android destruction")
            } else if scenario == "identity" {
                let marker = save.appendingPathComponent("java-web-store.json"), original = try Data(contentsOf: marker)
                try JSONSerialization.data(withJSONObject: ["id": UUID().uuidString]).write(to: marker, options: .atomic)
                try await stop(success: false)
                try check(session.error?.contains("存档标识") == true, "supervisor checks launch identity, checkpoint and current save marker")
                try original.write(to: marker, options: .atomic)
            } else {
                _ = try await evaluate("setTimeout(()=>confirm('pending fixture decision'),0);true")
                try await session.wait(until: { preferences(save).contains("b pending_dialog true") || !session.active }, timeout: 10)
                try check(preferences(save).contains("b pending_dialog true"), "real WebKit decision is pending before close")
                try await stop()
                try check(preferences(save).contains("i destroyed 1"), "Android final preferences committed")
                if scenario == "legacy" {
                    try check(identity.legacyPackage == imported.packageName, "existing Android data adopts legacy package store")
                    // Frozen from the pre-build-8 Objective-C package hash.
                    try check(identity.id == UUID(uuidString: "C7020BE8-5B59-43B2-8BF2-5A72363F9E96"), "legacy UUID matches the original package store")
                    try FileManager.default.removeItem(at: save.appendingPathComponent("java-web-store.json"))
                }
                try await start(repository, imported, paths)
                let reopened = try await javascriptAsync("return await readSave();") as? [String: Any] ?? [:]
                try check(reopened["local"] as? String == "retained" && reopened["indexed"] as? String == "retained" && reopened["hidden"] as? String == "saved", "localStorage, IndexedDB and pagehide writes survive process reopen")
                try await session.wait(until: { preferences(save).contains("retained=1") || !session.active }, timeout: 5)
                try check(preferences(save).contains("retained=1"), "final CookieManager write survives reopen")
                try check(try WebStorage.readJavaStore(in: save) == identity, "save identity is stable across launch and legacy adoption")
                try await stop()
                try await start(otherRepository, other, otherPaths)
                let isolated = try await javascriptAsync("return await readSave();") as? [String: Any] ?? [:]
                try check(isolated["local"] is NSNull && isolated["indexed"] is NSNull, "same package in another library has independent web data")
                _ = try await javascriptAsync("return await persist('other');")
                try await stop()
                let otherIdentity = try WebStorage.readJavaStore(in: otherSave)
                try check(otherIdentity.id != identity.id && otherIdentity.legacyPackage == nil, "new saves receive isolated store IDs")
                try check(try await storeExists(identity.id), "NativeRunner owns the persistent store")
                // Failed cleanup must retain the marker and Android data.
                if scenario != "legacy" {
                    do { try await repository.deleteSave(imported.id, javaHelper: URL(fileURLWithPath: "/nonexistent-husk-helper")); throw LibraryFailure("Missing helper was accepted") }
                    catch { try check(FileManager.default.fileExists(atPath: save.appendingPathComponent("data").path) && (try WebStorage.readJavaStore(in: save)) == identity, "failed removal preserves both store marker and Android data") }
                }
                try await repository.deleteSave(imported.id, javaHelper: helper)
                try check(try await storeExists(identity.id) == (scenario == "legacy"), "isolated store deleted; shared legacy store preserved")
                try await start(repository, imported, paths)
                let replacement = try WebStorage.readJavaStore(in: save)
                let empty = try await javascriptAsync("return await readSave();") as? [String: Any] ?? [:]
                try check(replacement.id != identity.id && replacement.legacyPackage == nil && empty["local"] is NSNull && empty["indexed"] is NSNull, "cleared save restarts with empty independent web state")
                try await stop()
                try await start(otherRepository, other, otherPaths)
                let retained = try await javascriptAsync("return await readSave();") as? [String: Any] ?? [:]
                try check(retained["local"] as? String == "other" && retained["indexed"] as? String == "other", "clearing one save preserves another library's state")
                try await stop(); try await otherRepository.deleteSave(other.id, javaHelper: helper)
                if scenario == "legacy" {
                    // This package UUID belongs only to this repository fixture.
                    // Product deletion intentionally retains shared legacy data.
                    let cleanup = Process(); cleanup.executableURL = helper; cleanup.arguments = ["--delete-web-store", identity.id.uuidString]
                    cleanup.standardOutput = FileHandle.nullDevice; cleanup.standardError = FileHandle.nullDevice
                    try cleanup.run()
                    while cleanup.isRunning { try await Task.sleep(for: .milliseconds(50)) }
                    try check(cleanup.terminationStatus == 0, "disposable legacy fixture cleaned up")
                }
            }
            try await repository.deleteSave(imported.id, javaHelper: helper)
            print("PASS Java WebView \(scenario): \(root.path)")
        } catch {
            if session.active { session.stop(); try? await session.wait(until: { !session.active }, timeout: 35) }
            print("FAIL \(error.localizedDescription); logs: \(root.path)"); exit(1)
        }
    }
}
