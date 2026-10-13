// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import WebKit
import SharedLibrary

enum HuskLog {
    static func log(_ category: String, _ message: String) {
        try? FileHandle.standardError.write(contentsOf: Data("[\(category)] \(message)\n".utf8))
    }
}

@MainActor final class WebRunner: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var options: [String: String] = [:], splits: [String] = []
    var flags = Set<String>()
    var session = "", state = "starting", sequence = 0
    var runtime: WebAppRuntime?, window: NSWindow?, store: WKWebsiteDataStore?
    var inputCover: NSView?
    var checkpoint: URL!, storeID: UUID!
    var timer: Timer?, input = Data(), finished = false, transitioning = false
    var pauseInactive = false, pausedByFocus = false
    var hidden: Bool { flags.contains("--headless") || flags.contains("--hidden-window") }
    var automation: Bool { flags.contains("--automation") }

    override init() {
        super.init()
        var args = Array(CommandLine.arguments.dropFirst())
        let switches: Set<String> = ["--headless", "--hidden-window", "--show-window", "--automation", "--mute", "--pause-inactive", "--fullscreen"]
        while !args.isEmpty {
            let name = args.removeFirst()
            if switches.contains(name) { flags.insert(name) }
            else if !args.isEmpty {
                let value = args.removeFirst()
                if name == "--split" { splits.append(value) } else { options[name] = value }
            }
        }
        session = options["--session"] ?? ""
        pauseInactive = flags.contains("--pause-inactive")
    }
    func event(_ name: String, _ detail: [String: Any] = [:]) {
        sequence += 1
        var message = detail
        message.merge(["protocol": 1, "session": session, "pid": ProcessInfo.processInfo.processIdentifier,
                       "seq": sequence, "event": name, "state": state, "runtime": "web"]) { _, new in new }
        if let data = try? JSONSerialization.data(withJSONObject: message) {
            try? FileHandle.standardOutput.write(contentsOf: data + Data([10]))
        }
    }
    func fail(_ reason: String) {
        guard !finished else { return }
        state = "failed"; event("failed", ["reason": reason]); finish(1)
    }
    func finish(_ code: Int32) {
        finished = true; timer?.invalidate(); FileHandle.standardInput.readabilityHandler = nil
        runtime?.webView.stopLoading(); window?.orderOut(nil)
        NSApp.stop(nil)
        // NSApplication.run may be waiting for an event after stop.
        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: false) }
        exitCode = code
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let raw = options["--delete-store"], let id = UUID(uuidString: raw) {
            // Initialize WebKit's main run loop before its static data-store IO
            // API. The persistent store being removed is never instantiated.
            let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
            let bootstrap = WKWebView(frame: .zero, configuration: config)
            WKWebsiteDataStore.remove(forIdentifier: id) { error in
                if let error { HuskLog.log("web", "remove store: \(error)") }
                self.finish(error == nil ? 0 : 1)
                withExtendedLifetime(bootstrap) {}
            }
            return
        }
        do {
            guard UUID(uuidString: session) != nil, options["--runtime"] == "web",
                  let apk = options["--apk"], let hash = options["--apk-sha256"],
                  let path = options["--checkpoint"], let package = options["--package"],
                  package.range(of: "^[A-Za-z0-9_.$]+$", options: .regularExpression) != nil,
                  let rawKind = options["--web-kind"], let kind = WebAppKind(rawValue: rawKind) else { throw LibraryFailure("Web 运行参数不完整。") }
            checkpoint = URL(fileURLWithPath: path)
            let save = checkpoint.deletingLastPathComponent()
            let assets = try WebStorage.assets(apks: ([apk] + splits).map { URL(fileURLWithPath: $0) }, digest: hash, save: save, engine: kind.name)
            storeID = try WebStorage.identifier(in: save); store = WKWebsiteDataStore(forIdentifier: storeID)
            let rect = NSRect(x: 0, y: 0, width: 900, height: 620)
            let win = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window = win; win.title = options["--title"] ?? package; win.delegate = self; win.isReleasedWhenClosed = false
            win.minSize = NSSize(width: 360, height: 300); win.center()
            let web = WebAppRuntime(kind: kind, package: package, label: win.title, version: "1.0", assets: assets, dataDir: save, store: store, lifecycleScript: WebLifecycle.script)
            runtime = web; web.webView.frame = rect; web.webView.autoresizingMask = [.width, .height]
            let content = NSView(frame: rect); win.contentView = content
            content.addSubview(web.webView)
            let cover = NSView(frame: rect); cover.autoresizingMask = [.width, .height]; cover.isHidden = true
            content.addSubview(cover); inputCover = cover
            installMenu()
            web.onReady = { [weak self] in
                guard let self, self.state == "starting" else { return }
                self.state = "running"; self.event("ready")
                if !self.hidden {
                    win.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
                    if self.flags.contains("--fullscreen") { win.toggleFullScreen(nil) }
                }
            }
            web.onFailure = { [weak self] reason in self?.fail(reason) }
            web.onClose = { [weak self] in self?.stop() }
            if flags.contains("--mute") { web.webView.setAllMediaPlaybackSuspended(true, completionHandler: nil) }
            event("starting")
            FileHandle.standardInput.readabilityHandler = { handle in
                let bytes = handle.availableData
                DispatchQueue.main.async { if bytes.isEmpty { self.stop() } else { self.consume(bytes) } }
            }
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.event("status") }
            }
        } catch { fail(error.localizedDescription) }
    }
    func consume(_ bytes: Data) {
        input.append(bytes)
        guard input.count <= 262_144 else { fail("控制消息过大。"); return }
        while let end = input.firstIndex(of: 10) {
            let line = input[..<end]; input.removeSubrange(...end)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  message["protocol"] as? Int == 1, message["session"] as? String == session,
                  let command = message["command"] as? String else { fail("控制消息无效。"); return }
            switch command {
            case "stop": stop()
            case "pause": pause(true)
            case "resume": pause(false)
            case "set-pause-inactive": pauseInactive = message["enabled"] as? Bool ?? false
            case "window":
                guard !hidden else { continue }
                switch message["action"] as? String {
                case "show": window?.deminiaturize(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
                case "minimize": window?.miniaturize(nil)
                case "zoom": window?.zoom(nil)
                case "fullscreen": window?.toggleFullScreen(nil)
                default: break
                }
            case "back": if state == "running" { runtime?.back() }
            case "evaluate" where automation:
                guard let script = message["script"] as? String, let web = runtime?.webView, ["running", "paused"].contains(state) else { continue }
                web.evaluateJavaScript(script) { value, error in
                    self.event("evaluation", ["request": message["request"] as? String ?? "", "value": value ?? NSNull(), "error": error?.localizedDescription ?? ""])
                }
            default: break
            }
        }
    }
    func pause(_ paused: Bool) {
        guard !transitioning, state == (paused ? "running" : "paused"), let runtime else { return }
        transitioning = true
        Task { @MainActor in
            do {
                runtime.setActive(!paused)
                _ = try await runtime.webView.evaluateJavaScript("window.__huskPauseTimers && window.__huskPauseTimers(\(paused)); true")
                await runtime.webView.setAllMediaPlaybackSuspended(paused || flags.contains("--mute"))
                guard state != "stopping" else { return }
                inputCover?.isHidden = !paused
                window?.makeFirstResponder(paused ? nil : runtime.webView)
                state = paused ? "paused" : "running"; transitioning = false; event("lifecycle")
            } catch { fail(error.localizedDescription) }
        }
    }
    func stop() {
        guard !finished, !["stopping", "failed", "exited"].contains(state) else { return }
        state = "stopping"; event("stopping")
        Task { @MainActor in
            do {
                guard let runtime, let store else { throw LibraryFailure("Web 运行组件尚未启动。") }
                runtime.setActive(false)
                _ = try await runtime.webView.evaluateJavaScript("window.dispatchEvent(new Event('pagehide')); true")
                await runtime.webView.setAllMediaPlaybackSuspended(true)
                // Destroy the document before acknowledging release of the host view.
                // Public WebKit APIs do not promise a disk fsync; persistence remains
                // owned by WebKit's network process, not a native storage-closed claim.
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    runtime.onReady = { [weak runtime] in
                        runtime?.onReady = nil; runtime?.onFailure = nil; continuation.resume()
                    }
                    runtime.onFailure = { [weak runtime] reason in
                        runtime?.onReady = nil; runtime?.onFailure = nil; continuation.resume(throwing: LibraryFailure(reason))
                    }
                    runtime.webView.loadHTMLString("<!doctype html><title>Closed</title>", baseURL: nil)
                }
                runtime.onReady = nil; runtime.onFailure = nil
                _ = await store.httpCookieStore.allCookies()
                _ = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
                runtime.webView.stopLoading(); runtime.webView.removeFromSuperview()
                runtime.webView.navigationDelegate = nil; runtime.webView.uiDelegate = nil
                self.runtime = nil; self.store = nil
                try WebStorage.receipt(["session": session, "runtime": "web", "lifecycle": "detached",
                    "storage": "webkit-managed", "store": storeID.uuidString], to: checkpoint)
                event("web-storage-detached", ["lifecycle": "detached", "storage": "webkit-managed", "store": storeID.uuidString as String])
                state = "exited"; event("exited"); finish(0)
            } catch { fail(error.localizedDescription) }
        }
    }
    func installMenu() {
        let menu = NSMenu()
        let application = NSMenuItem(); menu.addItem(application)
        let actions = NSMenu(title: "Husk Web"); application.submenu = actions
        let back = actions.addItem(withTitle: "返回", action: #selector(goBack), keyEquivalent: "["); back.target = self
        let pause = actions.addItem(withTitle: "暂停 / 继续", action: #selector(togglePause), keyEquivalent: "p"); pause.target = self
        actions.addItem(.separator())
        actions.addItem(withTitle: "结束应用", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenuItem(); menu.addItem(edit); edit.submenu = NSMenu(title: "编辑")
        for (title, action, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.submenu?.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        NSApp.mainMenu = menu
    }
    @objc func goBack() { if state == "running" { runtime?.back() } }
    @objc func togglePause() { pause(state != "paused") }
    func windowShouldClose(_ sender: NSWindow) -> Bool { stop(); return false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { stop(); return .terminateCancel }
    func windowDidResignKey(_ notification: Notification) {
        if pauseInactive && state == "running" { pausedByFocus = true; pause(true) }
    }
    func windowDidBecomeKey(_ notification: Notification) {
        if pausedByFocus { pausedByFocus = false; pause(false) }
    }
}

var exitCode: Int32 = 0
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = WebRunner()
    app.delegate = delegate
    app.setActivationPolicy(delegate.hidden || delegate.options["--delete-store"] != nil ? .prohibited : .regular)
    app.run()
    withExtendedLifetime(delegate) {}
}
exit(exitCode)
