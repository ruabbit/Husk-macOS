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
            func waitForStop(success: Bool = true) async throws {
                try await session.wait(until: { !session.active }, timeout: 35)
                let receipts = session.events.filter { $0["event"] as? String == "storage-closed" }
                if success {
                    try check(session.state == "exited" && session.error == nil, session.error ?? "Android destroyed, WebKit detached, child reaped")
                    let web = receipts.first?["web"] as? [String: Any]
                    try check(receipts.count == 1 && web?["lifecycle"] as? String == "detached" && web?["storage"] as? String == "webkit-managed" && web?["saveStage"] as? String == "prepared", "one composite receipt retains native, save-stage and WebKit ownership")
                } else { try check(session.state == "failed" && session.error != nil, "incomplete or mismatched shutdown rejected") }
            }
            func stop(success: Bool = true) async throws {
                session.stop(); try await waitForStop(success: success)
            }
            if scenario == "legacy" {
                _ = try await repository.prepare(imported.id)
                try FileManager.default.createDirectory(at: save.appendingPathComponent("data"), withIntermediateDirectories: true)
            }
            try await start(repository, imported, paths)
            let identity = try WebStorage.readJavaStore(in: save)
            _ = try await javascriptAsync("return await persist('retained');")
            if scenario.hasPrefix("http-") {
                guard let origin = ProcessInfo.processInfo.environment["HUSK_WEB_HTTP_ORIGIN"],
                      let originURL = URL(string: origin), originURL.host == "127.0.0.1" else {
                    throw LibraryFailure("HTTP test needs its isolated loopback server")
                }
                func awaitHTTP(_ path: String) async throws {
                    var ready = false
                    for _ in 0..<160 {
                        if try await evaluate("window.fixtureReady===true && location.origin==='\(origin)' && location.pathname==='\(path)' && !window.__huskClosing", optional: true) as? Bool == true { ready = true; break }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                    try check(ready && session.state == "running", "HTTP document \(path) is loaded and live")
                }
                func loadHTTP() async throws {
                    _ = try await evaluate("nativeSave.loadRemote('\(origin)/start');true")
                    try await awaitHTTP("/start")
                }
                func requests() async throws -> [[String: Any]] {
                    let (data, _) = try await URLSession.shared.data(from: originURL.appendingPathComponent("report"))
                    return try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
                }
                func assertCount(_ path: String, _ expected: Int) async throws {
                    let count = try await requests().filter { $0["path"] as? String == path }.count
                    try check(count == expected, "HTTP \(path) request count \(count) == \(expected)")
                }
                func saveHTTP(_ value: String, delay: Int = 100, rejection: Bool = false, timeout: Bool = false) async throws {
                    let wait = timeout ? "new Promise(()=>{})" : rejection ?
                        "new Promise((r,j)=>setTimeout(()=>j(new Error('HTTP save rejected')),\(delay)))" : "new Promise(r=>setTimeout(r,\(delay)))"
                    _ = try await evaluate("addEventListener('pagehide',e=>{nativeSave.store();e.waitUntil(\(wait).then(()=>persist('\(value)')).then(async()=>{document.cookie='final_cookie=retained; Max-Age=3600; Path=/';const r=await fetch('/saved',{method:'POST',body:'\(value)'});if(!r.ok)throw Error('save HTTP failed');nativeSave.store();nativeSave.recordUI();}));});true")
                }
                try await loadHTTP()
                _ = try await javascriptAsync("return await persist('http-initial');")
                if scenario == "http-history" {
                    try await saveHTTP("before-redirect")
                    _ = try await evaluate("location.href='/redirect';true")
                    try await awaitHTTP("/second")
                    try await assertCount("/start", 1); try await assertCount("/redirect", 1); try await assertCount("/second", 1)
                    try check(try await evaluate("localStorage.getItem('pagehideCount')==='1' && localStorage.getItem('value')==='before-redirect'") as? Bool == true, "HTTP redirect retires the source document exactly once")
                    try await saveHTTP("before-back")
                    _ = try await evaluate("nativeSave.history('back');true")
                    try await awaitHTTP("/start")
                    try await assertCount("/start", 2)
                    try check(try await evaluate("localStorage.getItem('pagehideCount')==='2' && localStorage.getItem('value')==='before-back'") as? Bool == true, "HTTP history uses saved data without another unload or duplicate request")
                    _ = try await evaluate("nativeSave.history('forward');true")
                    try await awaitHTTP("/second")
                    try await assertCount("/second", 2); try await assertCount("/redirect", 1)
                    try await stop()
                } else {
                    let rejected = scenario == "http-stop-rejected" || scenario == "http-stop-timeout"
                    let racing = scenario != "http-save"
                    try await saveHTTP("http-saved", delay: racing ? 1500 : 100, rejection: scenario == "http-stop-rejected", timeout: scenario == "http-stop-timeout")
                    if racing {
                        _ = try await evaluate("location.href='/second';true")
                        try await session.wait(until: { preferences(save).contains("i bridge_calls 1") || !session.active }, timeout: 10)
                        try check(session.state == "running" && !preferences(save).contains("b view_ui_saved true"), "host stop overlaps the document's unfinished save")
                    }
                    if scenario == "http-stop-timeout" { try await Task.sleep(for: .milliseconds(3500)) }
                    let stoppedAt = Date()
                    try await stop(success: !rejected)
                    if scenario == "http-stop-timeout" {
                        try check(Date().timeIntervalSince(stoppedAt) < 4.5, "host stop retains the original navigation save deadline")
                    }
                    if racing { try await assertCount("/second", 0) }
                    if rejected {
                        try await assertCount("/saved", 0)
                        try check(!session.events.contains { $0["event"] as? String == "storage-closed" }, "rejected or timed-out HTTP save cannot acknowledge storage")
                    } else {
                        try await assertCount("/saved", 1)
                        try check(preferences(save).contains("i bridge_calls 2") && preferences(save).contains("i bridge_main_calls 2") && preferences(save).contains("b view_ui_saved true"), "HTTP save completed plugin and queued UI writes before Android destruction")
                        try await start(repository, imported, paths)
                        try await loadHTTP()
                        let restored = try await javascriptAsync("return await readSave();") as? [String: Any] ?? [:]
                        try check(restored["local"] as? String == "http-saved" && restored["indexed"] as? String == "http-saved", "HTTP localStorage and IndexedDB survive a real process reopen")
                        try check(try await evaluate("document.cookie.includes('final_cookie=retained') && !document.cookie.includes('fixture_http=') && nativeSave.cookieFor('\(origin)/start').includes('fixture_http=server') && nativeSave.previous()===2 && localStorage.getItem('pagehideCount')==='1' && localStorage.getItem('unloadCount')==='1'") as? Bool == true, "HTTP cookies, Java plugin state and single lifecycle survive reopen")
                        let starts = try await requests().filter { $0["path"] as? String == "/start" }
                        try check(starts.count == 2 && (starts.last?["cookie"] as? String ?? "").contains("final_cookie=retained"), "reopened HTTP request sends its persisted cookie")
                        try await stop()
                    }
                }
            } else if scenario.hasPrefix("view-") {
                let failed = ["view-rejected", "view-plugin-failed", "view-timeout", "view-message-failed"].contains(scenario)
                if scenario.hasPrefix("view-message") {
                    try check(try await evaluate("nativeSave.installListener(\(scenario == "view-message-failed" ? "true" : "false"))") as? Bool == true, "APK AndroidX boundary listener installed")
                    _ = try await javascriptAsync("while(typeof nativeMessage==='undefined')await new Promise(r=>setTimeout(r,10));return true;")
                    _ = try await evaluate("addEventListener('pagehide',e=>{e.waitUntil(new Promise(resolve=>{nativeMessage.onmessage=()=>resolve();nativeMessage.postMessage('from-listener');}));});true")
                }
                let work = scenario == "view-rejected" ? "e.waitUntil(Promise.reject(new Error('View save rejected')));" :
                    scenario == "view-plugin-failed" ? "try{nativeSave.fail();}catch(e){}" :
                    scenario == "view-timeout" ? "e.waitUntil(new Promise(()=>{}));" :
                    "nativeSave.store();e.waitUntil(new Promise(resolve=>setTimeout(resolve,1500)).then(()=>persist('from-view-destroy')).then(()=>{nativeSave.store();nativeSave.recordUI();}));"
                _ = try await evaluate("addEventListener('pagehide',e=>{\(work)});nativeSave.retire('\(scenario == "view-duplicate" ? "duplicate" : scenario == "view-only" ? "only" : "normal")');true")
                try await session.wait(until: { preferences(save).contains("b view_retired true") || !session.active }, timeout: 10)
                try check(session.state == "running", "destroying one WebView preserves the running Activity")
                var replaced = scenario == "view-only"
                for _ in 0..<(scenario == "view-only" ? 0 : 120) {
                    if try await evaluate("window.fixtureReady===true && nativeSave.viewGeneration()===1", optional: true) as? Bool == true { replaced = true; break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                try check(replaced && session.state == "running", scenario == "view-only" ? "Activity continues with no WebView" : "new WebView loads and bridges while its predecessor retires")
                try check(!session.events.contains { $0["state"] as? String == "stopping" }, "per-view retirement does not stop the session")
                if scenario == "view-stop-race" {
                    try check(!preferences(save).contains("b view_ui_saved true"), "old document is still in its asynchronous save at host stop")
                    try await stop()
                } else {
                    if scenario == "view-paused" {
                        session.togglePause()
                        try await session.wait(until: { session.state == "paused" || !session.active }, timeout: 10)
                        try check(session.state == "paused", "replacement Activity pauses while its old WebView saves")
                    }
                    if !failed {
                        try await session.wait(until: { preferences(save).contains("b view_ui_saved true") || !session.active }, timeout: 10)
                        if scenario == "view-paused" {
                            session.togglePause()
                            try await session.wait(until: { session.state == "running" || !session.active }, timeout: 10)
                        }
                        if scenario != "view-only" {
                            let state = try await javascriptAsync("return await readSave();") as? [String: Any] ?? [:]
                            try check(state["local"] as? String == "from-view-destroy" && state["indexed"] as? String == "from-view-destroy", "retired document saved localStorage and IndexedDB while session continued")
                            try check(try await evaluate("localStorage.getItem('pagehideCount')==='1' && localStorage.getItem('unloadCount')==='1'") as? Bool == true, "destroyed document delivers save lifecycle once")
                        }
                    }
                    try await stop(success: !failed)
                }
                if failed {
                    try check(!session.events.contains { $0["event"] as? String == "storage-closed" }, "retired view failure stays sticky through successful replacement and final shutdown")
                } else {
                    try check(preferences(save).contains("i bridge_calls 2") && preferences(save).contains("b view_ui_saved true"), "retired Java plugin and queued UI writes completed")
                    if scenario == "view-message" {
                        try check(preferences(save).contains("listener_saved") && preferences(save).contains("from-listener") && preferences(save).contains("b listener_ui_saved true"), "AndroidX listener delivered and replied before detach")
                    }
                    try await start(repository, imported, paths)
                    let restored = try await javascriptAsync("return await readSave();") as? [String: Any] ?? [:]
                    try check(restored["local"] as? String == "from-view-destroy" && restored["indexed"] as? String == "from-view-destroy", "per-view saved state survives process reopen")
                    try check(try await evaluate("nativeSave.previous()") as? Int == 2, "per-view Java save survives process reopen")
                    try await stop()
                }
            } else if ["navigation-policy-blocked", "navigation-policy-allowed", "navigation-fragment", "navigation-sequential", "navigation-history", "navigation-post-history"].contains(scenario) {
                func awaitPage(_ query: String) async throws {
                    var ready = false
                    for _ in 0..<240 {
                        if try await evaluate("window.fixtureReady===true && location.search==='\(query)' && !window.__huskClosing", optional: true) as? Bool == true { ready = true; break }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                    if !ready { print("Navigation diagnostic: \(try await evaluate("({url:location.href,ready:window.fixtureReady,closing:window.__huskClosing,persisted:window.fixturePageshowPersisted,hide:localStorage.getItem('pagehideCount'),token:window.navigationDocument})", optional: true))") }
                    try check(ready && session.state == "running", "replacement document is loaded, live and still in the Activity")
                }
                func installSave(_ value: String, delay: Int = 20) async throws {
                    _ = try await evaluate("addEventListener('pagehide',e=>{nativeSave.store();e.waitUntil(new Promise(r=>setTimeout(r,\(delay))).then(()=>persist('\(value)')).then(()=>nativeSave.store()));});true")
                }
                if scenario == "navigation-post-history" {
                    _ = try await evaluate("nativeSave.postPage();true")
                    try await awaitPage("?posted")
                    try check(preferences(save).contains("i post_requests 1"), "fixture main document was loaded by POST once")
                    try await installSave("post-save")
                    _ = try await evaluate("location.href='?after-post';true")
                    try await awaitPage("?after-post")
                    _ = try await evaluate("nativeSave.history('back');true")
                    try await session.wait(until: { preferences(save).contains("navigation_error") || !session.active }, timeout: 5)
                    try check(try await evaluate("location.search==='?after-post' && !window.__huskClosing && nativeSave.previous()===2") as? Bool == true, "non-GET history is rejected before retiring the current document")
                    try await stop()
                    try check(preferences(save).contains("i post_requests 1"), "history restore never resubmits the POST request")
                    try await repository.deleteSave(imported.id, javaHelper: helper)
                    print("PASS Java WebView \(scenario): \(root.path)")
                    return
                } else if scenario == "navigation-policy-blocked" {
                    _ = try await evaluate("window.ticks=0;setInterval(()=>ticks++,25);location.href='?blocked';true")
                    try await session.wait(until: { preferences(save).contains("?blocked") || !session.active }, timeout: 5)
                    try check(preferences(save).contains("b navigation_main true"), "Java WebViewClient receives main-document policy before saving")
                    for _ in 0..<40 {
                        if try await evaluate("ticks>0") as? Bool == true { break }
                        try await Task.sleep(for: .milliseconds(25))
                    }
                    try check(try await evaluate("location.search==='' && !window.__huskClosing && !localStorage.getItem('pagehideCount') && ticks>0 && nativeSave.previous()===0") as? Bool == true, "vetoed navigation leaves lifecycle, timers and Java plugins live")
                    _ = try await evaluate("location.href='husk-fixture:intercept';true")
                    try await session.wait(until: { preferences(save).contains("husk-fixture:intercept") || !session.active }, timeout: 5)
                    try check(try await evaluate("!window.__huskClosing && !localStorage.getItem('pagehideCount') && nativeSave.previous()===0") as? Bool == true, "custom URL handling does not seal the current page")
                } else if scenario == "navigation-fragment" {
                    _ = try await evaluate("window.ticks=0;setInterval(()=>ticks++,25);location.hash='section';true")
                    try await Task.sleep(for: .milliseconds(200))
                    try check(try await evaluate("location.hash==='#section' && !window.__huskClosing && !localStorage.getItem('pagehideCount') && ticks>0 && nativeSave.previous()===0") as? Bool == true, "fragment navigation preserves the same document and its running plugins")
                    _ = try await evaluate("nativeSave.history('back');true")
                    try await Task.sleep(for: .milliseconds(200))
                    try check(try await evaluate("location.hash==='' && !window.__huskClosing && !localStorage.getItem('pagehideCount')") as? Bool == true, "fragment history back does not unload the document")
                    _ = try await evaluate("nativeSave.history('forward');true")
                    try await Task.sleep(for: .milliseconds(200))
                    try check(try await evaluate("location.hash==='#section' && !window.__huskClosing && !localStorage.getItem('pagehideCount')") as? Bool == true, "fragment history forward does not unload the document")
                    try await installSave("fragment-replaced")
                    _ = try await evaluate("window.navigationDocument='before-base';nativeSave.loadBase();true")
                    for _ in 0..<160 {
                        if try await evaluate("!window.navigationDocument && window.fixtureReady===true && location.hash===''", optional: true) as? Bool == true { break }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                    try check(try await evaluate("!window.navigationDocument && !window.__huskClosing && localStorage.getItem('pagehideCount')==='1' && localStorage.getItem('value')==='fragment-replaced'") as? Bool == true, "explicit base-URL load after a fragment still saves and replaces the document")
                } else {
                    try await installSave("policy-save", delay: scenario == "navigation-sequential" ? 2200 : 20)
                    _ = try await evaluate("location.href='?allowed';true")
                    try await awaitPage("?allowed")
                    try check(preferences(save).contains("?allowed") && preferences(save).contains("i navigation_calls 1"), "allowed page navigation reaches Java policy exactly once")
                    let saved = try await javascriptAsync("return await readSave();") as? [String: Any] ?? [:]
                    try check(saved["local"] as? String == "policy-save" && saved["indexed"] as? String == "policy-save", "allowed navigation waits for Java plugins and both Web stores")
                    if scenario == "navigation-sequential" {
                        try await installSave("second-save", delay: 4500)
                        _ = try await evaluate("location.href='?second';true")
                        try await awaitPage("?second")
                        let second = try await javascriptAsync("return await readSave();") as? [String: Any] ?? [:]
                        try check(second["indexed"] as? String == "second-save" && preferences(save).contains("i bridge_calls 4"), "previous document deadline cannot abort the next document save")
                    } else if scenario == "navigation-history" {
                        try await installSave("reload-save")
                        _ = try await evaluate("window.navigationDocument='before-reload';nativeSave.history('reload');true")
                        // Observe the committed new document, not the old page before its policy callback.
                        for _ in 0..<160 {
                            if try await evaluate("localStorage.getItem('pagehideCount')==='2' && !window.navigationDocument && !window.__huskClosing && window.fixtureReady===true", optional: true) as? Bool == true { break }
                            try await Task.sleep(for: .milliseconds(50))
                        }
                        try check(try await evaluate("localStorage.getItem('pagehideCount')==='2' && !window.navigationDocument && !window.__huskClosing") as? Bool == true, "reload saves the old page once and installs a live replacement")
                        try await installSave("back-save")
                        _ = try await evaluate("nativeSave.history('back');true")
                        try await awaitPage("")
                        try check(try await evaluate("localStorage.getItem('value')==='back-save' && nativeSave.previous()===6") as? Bool == true, "back saves and restores a live document with plugin access")
                        try await installSave("forward-save")
                        _ = try await evaluate("nativeSave.history('forward');true")
                        try await awaitPage("?allowed")
                        try check(try await evaluate("localStorage.getItem('value')==='forward-save' && nativeSave.previous()===8") as? Bool == true, "forward saves and restores a live document with plugin access")
                    }
                }
                try await stop()
                try await start(repository, imported, paths)
                if scenario == "navigation-sequential" {
                    let restored = try await javascriptAsync("return await readSave();") as? [String: Any] ?? [:]
                    try check(restored["local"] as? String == "second-save" && restored["indexed"] as? String == "second-save", "successive navigation writes survive process reopen")
                }
                try await stop()
            } else if scenario == "navigation-save" || scenario == "navigation-rejected" || scenario == "navigation-plugin-failed" {
                let rejected = scenario != "navigation-save"
                let handler = scenario == "navigation-plugin-failed" ? "try{nativeSave.fail();}catch(e){}" : rejected
                    ? "nativeSave.store();e.waitUntil(new Promise(()=>{}));"
                    : "nativeSave.store();e.waitUntil(new Promise(resolve=>setTimeout(resolve,1500)).then(()=>persist('from-navigation')).then(()=>nativeSave.store()));"
                try check(try await evaluate("typeof nativeSave.store==='function' && typeof nativeSave.navigate==='function' && typeof persist==='function'") as? Bool == true, "real Java bridge and Web storage are available before navigation")
                _ = try await evaluate("addEventListener('pagehide',e=>{\(handler)});true")
                _ = try await evaluate("nativeSave.navigate();true")
                if rejected {
                    try await Task.sleep(for: .seconds(scenario == "navigation-plugin-failed" ? 1 : 7))
                    try check(session.state == "running", "rejected navigation remains in the existing Activity")
                    let current = try await evaluate("location.search") as? String ?? ""
                    try check(current != "?next", "failed or timed out navigation is cancelled before replacing the document")
                    try await stop(success: false)
                    try check(!session.events.contains { $0["event"] as? String == "storage-closed" }, "navigation save failure never acknowledges storage")
                } else {
                    var navigated = false
                    for _ in 0..<200 {
                        if try await evaluate("window.fixtureReady===true && location.search==='?next'", optional: true) as? Bool == true { navigated = true; break }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                    try check(navigated && session.state == "running", "same WebView navigation commits after the old save stage")
                    let state = try await javascriptAsync("return await readSave();") as? [String: Any] ?? [:]
                    try check(state["local"] as? String == "from-navigation" && state["indexed"] as? String == "from-navigation", "navigation preserves localStorage and IndexedDB before document replacement")
                    try check(try await evaluate("localStorage.getItem('pagehideCount')==='1' && localStorage.getItem('unloadCount')==='1'") as? Bool == true, "navigation delivers the old document lifecycle once")
                    try check(preferences(save).contains("i bridge_calls 2"), "navigation waits for both Java plugin writes")
                    try await stop()
                    try await start(repository, imported, paths)
                    let restored = try await javascriptAsync("return await readSave();") as? [String: Any] ?? [:]
                    try check(restored["local"] as? String == "from-navigation" && restored["indexed"] as? String == "from-navigation", "navigation save survives a real process reopen")
                    try await stop()
                }
            } else if scenario.hasPrefix("guest-") {
                if scenario == "guest-replace-first" || scenario == "guest-replace-last" {
                    _ = try await evaluate("nativeSave.replace(\(scenario == "guest-replace-first" ? "true" : "false"));true")
                    var replaced = false
                    for _ in 0..<120 {
                        if try await evaluate("window.fixtureReady===true && nativeSave.generation()===1", optional: true) as? Bool == true { replaced = true; break }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                    try check(replaced && session.state == "running", "queued replacement Activity survives finishing the old Activity")
                    try check(!session.events.contains { $0["state"] as? String == "stopping" }, "Activity replacement never requests whole-session stop")
                } else if scenario == "guest-child" {
                    _ = try await evaluate("nativeSave.child();true")
                    try await session.wait(until: { preferences(save).contains("b child_destroyed true") || !session.active }, timeout: 10)
                    try check(session.state == "running" && preferences(save).contains("i child_result 7"), "child finish delivers result and preserves the parent session")
                    try check(try await evaluate("nativeSave.generation()===0") as? Bool == true, "parent WebView survives child finish")
                }
                let failure = ["guest-rejected", "guest-timeout", "guest-destroy-failed"].contains(scenario)
                let handler = scenario == "guest-rejected" ? "e.waitUntil(Promise.reject(new Error('Guest save failure')));" : scenario == "guest-timeout" ? "e.waitUntil(new Promise(()=>{}));" : "nativeSave.store();e.waitUntil(new Promise(resolve=>setTimeout(resolve,20)).then(()=>persist('from-guest-finish')).then(()=>nativeSave.store()));"
                _ = try await evaluate("window.addEventListener('pagehide',e=>{\(handler)});true")
                if scenario == "guest-duplicate" {
                    _ = try await evaluate("window.addEventListener('pagehide',()=>nativeSave.replace(false));true")
                }
                if scenario == "guest-paused" {
                    _ = try await evaluate("nativeSave.closeOnPause();true")
                    session.togglePause()
                } else if scenario == "guest-affinity-stack" {
                    _ = try await evaluate("nativeSave.affinityChild();true")
                } else {
                    let mode = scenario == "guest-affinity" ? "affinity" : scenario == "guest-duplicate" ? "duplicate" : scenario == "guest-destroy-failed" ? "destroy-failed" : "normal"
                    _ = try await evaluate("nativeSave.close('\(mode)');true")
                }
                // The guest alone triggers this shutdown. Do not send host stop.
                try await waitForStop(success: !failure)
                if scenario == "guest-paused" { try check(preferences(save).contains("b finished_while_paused true"), "Activity onPause initiated the guest finish") }
                if scenario == "guest-affinity-stack" { try check(preferences(save).contains("b child_destroyed true"), "top Activity affinity closes both child and saved parent") }
                try check(session.events.filter { $0["event"] as? String == "state" && $0["state"] as? String == "stopping" && $0["reason"] as? String == "guest-quit" }.count == 1, "one guest-initiated stop handoff")
                if failure {
                    try check(!session.events.contains { $0["event"] as? String == "storage-closed" }, "guest save/destroy failure never acknowledges storage")
                } else {
                    try check(preferences(save).contains("i bridge_calls 2") && preferences(save).contains("i main_at_destroy 2"), "guest save plugins and queued UI writes finish before Activity destruction")
                    try await start(repository, imported, paths)
                    let restored = try await javascriptAsync("return await readSave();") as? [String: Any] ?? [:]
                    let previous = try await evaluate("nativeSave.previous()") as? Int
                    try check(restored["local"] as? String == "from-guest-finish" && restored["indexed"] as? String == "from-guest-finish" && previous == 2, "guest-initiated save persists across a real process reopen")
                    if !scenario.hasPrefix("guest-replace") {
                        try check(try await evaluate("localStorage.getItem('pagehideCount')==='1' && localStorage.getItem('unloadCount')==='1'") as? Bool == true, "guest close delivers lifecycle once")
                    }
                    try await stop()
                }
            } else if scenario == "save-bridge" || scenario == "save-paused" {
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
