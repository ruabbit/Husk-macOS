// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Combine
import Darwin

final class PipeReader: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func stop() { lock.lock(); cancelled = true; lock.unlock() }
    private var stopped: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func read(_ handle: FileHandle, receive: @escaping (Data) -> Void) {
        let fd = dup(handle.fileDescriptor)
        guard fd >= 0 else { receive(Data()); return }
        DispatchQueue.global(qos: .utility).async { [self] in
            defer { close(fd); receive(Data()) }
            var buffer = [UInt8](repeating: 0, count: 16_384)
            while !stopped {
                var event = pollfd(fd: fd, events: Int16(POLLIN | POLLHUP), revents: 0)
                let ready = poll(&event, 1, 100)
                if ready < 0 { if errno == EINTR { continue }; break }
                if ready == 0 { continue }
                let count = Darwin.read(fd, &buffer, buffer.count)
                if count < 0 && errno == EINTR { continue }
                if count <= 0 { break }
                receive(Data(buffer.prefix(count)))
            }
        }
    }
}

/// Owns one child. An engine is never reused in the library process.
@MainActor public final class SessionController: ObservableObject {
    @Published public private(set) var state = "idle"
    @Published public private(set) var gameID: String?
    @Published public private(set) var error: String?
    @Published public private(set) var latest: [String: Any] = [:]
    public private(set) var sessionID: String?
    public private(set) var pid: Int32 = 0
    public private(set) var events: [[String: Any]] = []
    public var active: Bool { process != nil }
    private var process: Process?
    private var commandPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var eventLog: FileHandle?
    private var diagnosticsLog: SessionDiagnostics?
    private var buffer = Data()
    private var sequence = 0
    private var checkpointReceived = false
    private var checkpoint: URL?
    private var stdoutEnded = false
    private var stderrEnded = false
    private var readers: [PipeReader] = []
    private var drainDeadline: Task<Void, Never>?
    private var exited: Int32?
    private var signalExit = false
    private var terminalEvent: String?
    private var watchdog: Task<Void, Never>?
    private var stopping: Task<Void, Never>?
    private var lastEvent = Date()
    private var startDate = Date()
    private var guestManagedStorage = false
    private var runtime: String?
    private var javaWebStore: WebStorage.JavaStore?

    private let languageDefaults: UserDefaults
    public init(languageDefaults: UserDefaults = .standard) { self.languageDefaults = languageDefaults; signal(SIGPIPE, SIG_IGN) }

    public func start(executable: URL, game: LibraryGame, apk: URL, checkpoint: URL,
                      logs: URL, headless: Bool = false, automation: Bool = false,
                      diagnostics: URL? = nil, hiddenWindow: Bool = false) throws {
        guard !active else { throw LibraryFailure("请先结束当前游戏。") }
        guard game.playable, let runtime = game.runtime else { throw LibraryFailure("此游戏尚未支持。") }
        try game.verifyExpansions(in: apk.deletingLastPathComponent())
        let geodeArguments = try Geode.arguments(game: game, apk: apk)
        let nativeArguments = runtime != "orbit" && runtime != "minecraft"
            ? NativeLaunch.arguments(apk: apk, package: game.packageName, nativeActivity: runtime == "nativeactivity" || runtime == "ue4") : []
        javaWebStore = (runtime == "java" || runtime == "nativeactivity") ? try WebStorage.javaStore(in: checkpoint.deletingLastPathComponent(), package: nativeArguments[1]) : nil
        guestManagedStorage = runtime != "orbit"
        self.runtime = runtime
        let id = UUID().uuidString
        let sessionLog = logs.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: sessionLog, withIntermediateDirectories: true)
        try Data().write(to: sessionLog.appendingPathComponent("events.jsonl"))
        eventLog = try FileHandle(forWritingTo: sessionLog.appendingPathComponent("events.jsonl"))
        diagnosticsLog = try SessionDiagnostics(directory: sessionLog)
        state = "starting"; gameID = game.id; sessionID = id; error = nil; latest = [:]; events = []
        sequence = 0; checkpointReceived = false; self.checkpoint = checkpoint
        stdoutEnded = false; stderrEnded = false; exited = nil; terminalEvent = nil; buffer = Data(); signalExit = false; pid = 0
        startDate = Date(); lastEvent = startDate
        let child = Process(), input = Pipe(), output = Pipe(), errors = Pipe()
        child.executableURL = executable
        child.arguments = ["--session", id, "--apk", apk.path, "--checkpoint", checkpoint.path,
                           "--apk-sha256", game.digest,
                           "--runtime", runtime, "--variant", String(game.fixture?.variant ?? 0), "--title", game.title]
        child.arguments! += nativeArguments
        if let javaWebStore { child.arguments! += ["--java-web-store", javaWebStore.id.uuidString] }
        if runtime == "web" { child.arguments! += ["--web-kind", game.engine == "Capacitor" ? "capacitor" : "cordova"] }
        child.arguments! += geodeArguments
        for name in game.apkNames.dropFirst() {
            child.arguments! += ["--split", apk.deletingLastPathComponent().appendingPathComponent(name).path]
        }
        if game.settings.openFullScreen && !headless && !hiddenWindow { child.arguments!.append("--fullscreen") }
        if hiddenWindow { child.arguments!.append("--hidden-window") }
        else if headless { child.arguments!.append("--headless") } else { child.arguments!.append("--show-window") }
        if game.settings.muted || headless { child.arguments!.append("--mute") }
        if game.settings.pauseWhenInactive { child.arguments!.append("--pause-inactive") }
        if automation { child.arguments!.append("--automation") }
        if let diagnostics { child.arguments! += ["--diagnostics", diagnostics.path] }
        child.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "TMPDIR": NSTemporaryDirectory(),
                             "TL_XMEM_MIB": guestManagedStorage ? "1024" : "64"]
        child.environment!.merge(AppLanguage.runnerEnvironment(languageDefaults)) { _, language in language }
        child.standardInput = input; child.standardOutput = output; child.standardError = errors
        commandPipe = input; outputPipe = output; errorPipe = errors; process = child
        child.terminationHandler = { [weak self] child in
            DispatchQueue.main.async {
                guard let self, self.sessionID == id else { return }
                self.exited = child.terminationStatus
                self.signalExit = child.terminationReason == .uncaughtSignal
                self.recordTermination(phase: "draining")
                self.finishIfReaped()
                if self.active {
                    self.drainDeadline = Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        guard !Task.isCancelled, let self, self.sessionID == id, self.active else { return }
                        self.error = self.error ?? "运行进程退出后未关闭输出通道。"
                        self.readers.forEach { $0.stop() }
                    }
                }
            }
        }
        do { try child.run() } catch {
            self.process = nil; state = "failed"; self.error = error.localizedDescription
            recordTermination(phase: "launch-failed")
            closePipes(); throw error
        }
        pid = child.processIdentifier
        // Close parent copies of child-facing ends so EOF is observable.
        try? output.fileHandleForWriting.close(); try? errors.fileHandleForWriting.close()
        try? input.fileHandleForReading.close()
        pump(output.fileHandleForReading, session: id, stderr: false)
        pump(errors.fileHandleForReading, session: id, stderr: true)
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled, let self, self.sessionID == id, self.active else { return }
                let timeout = self.state == "starting" ? (self.guestManagedStorage ? 90.0 : 20.0) : 8.0
                if Date().timeIntervalSince(self.lastEvent) > timeout {
                    self.fail("运行进程没有响应。日志保存在资料目录中。")
                    return
                }
            }
        }
    }

    private func pump(_ handle: FileHandle, session id: String, stderr: Bool) {
        let reader = PipeReader(); readers.append(reader)
        reader.read(handle) { [weak self] data in
                DispatchQueue.main.async {
                    guard let self, self.sessionID == id else { return }
                    if stderr {
                        // Guest diagnostics are separate from control messages.
                        if data.isEmpty { self.stderrEnded = true; self.finishIfReaped() }
                        else { self.diagnosticsLog?.append(data) }
                    } else if data.isEmpty {
                        self.stdoutEnded = true
                        if !self.buffer.isEmpty { self.fail("运行进程返回了不完整的消息。") }
                        self.finishIfReaped()
                    } else { self.consume(data) }
                }
        }
    }

    private func consume(_ data: Data) {
        guard error == nil else { return }
        buffer.append(data)
        guard buffer.count <= 262_144 else { fail("运行进程消息超过长度限制。"); return }
        while let end = buffer.firstIndex(of: 10) {
            let line = buffer[..<end]; buffer.removeSubrange(...end)
            guard line.count <= 65_536, let object = try? JSONSerialization.jsonObject(with: line),
                  let event = object as? [String: Any] else { fail("运行进程返回了无效消息。"); return }
            // An old session must never alter current state.
            guard event["session"] as? String == sessionID else { continue }
            guard event["protocol"] as? Int == 1, event["pid"] as? Int32 == pid,
                  let seq = event["seq"] as? Int, seq == sequence + 1,
                  let phase = event["state"] as? String, let kind = event["event"] as? String
            else { fail("运行进程协议校验失败。"); return }
            let transitions: [String: Set<String>] = [
                "starting": ["starting", "running", "stopping", "failed"],
                "running": ["running", "paused", "stopping", "failed"],
                "paused": ["paused", "running", "stopping", "failed"],
                "stopping": ["stopping", "exited", "failed"]]
            guard transitions[state]?.contains(phase) == true else { fail("运行进程状态顺序无效。"); return }
            sequence = seq; lastEvent = Date(); latest = event
            if events.count == 1000 { events.removeFirst(500) }
            events.append(event); try? eventLog?.write(contentsOf: Data(line) + Data([10]))
            if kind == "checkpoint" || kind == "storage-closed" || kind == "web-storage-detached" {
                let completed = runtime == "web"
                    ? kind == "web-storage-detached" && event["lifecycle"] as? String == "detached" && event["storage"] as? String == "webkit-managed"
                    : self.guestManagedStorage
                    ? kind == "storage-closed" && event["lifecycle"] as? String == "destroyed"
                    : kind == "checkpoint" && event["saved"] as? Bool == true
                guard phase == "stopping", completed,
                      let checkpoint, let data = try? Data(contentsOf: checkpoint),
                      let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      saved["session"] as? String == sessionID else { fail("未能确认游戏存档写入。"); return }
                if guestManagedStorage && (saved["runtime"] as? String != runtime || saved["lifecycle"] as? String != (runtime == "web" ? "detached" : "destroyed")) {
                    fail("运行组件没有完成存储关闭确认。"); return
                }
                if runtime == "web" {
                    guard saved["storage"] as? String == "webkit-managed", let store = saved["store"] as? String,
                          store == event["store"] as? String,
                          let identity = try? Data(contentsOf: checkpoint.deletingLastPathComponent().appendingPathComponent("web-store.json")),
                          (try? JSONDecoder().decode(UUID.self, from: identity))?.uuidString == store else {
                        fail("Web 存档标识不匹配。"); return
                    }
                }
                if runtime == "java" || runtime == "nativeactivity" {
                    guard let javaWebStore,
                          let web = saved["web"] as? [String: Any], javaWebStore.accepts(web),
                          let eventWeb = event["web"] as? [String: Any], NSDictionary(dictionary: web).isEqual(to: eventWeb),
                          (try? WebStorage.readJavaStore(in: checkpoint.deletingLastPathComponent())) == javaWebStore else {
                        fail("Java WebView 未完成存储托管确认，或存档标识不匹配。"); return
                    }
                }
                checkpointReceived = true
            }
            if phase == "failed" { error = event["reason"] as? String ?? "游戏启动失败。" }
            // A guest/window-initiated close needs the same bounded deadline as
            // the library's Stop button. Heartbeats must not extend it.
            if phase == "stopping" { startStopDeadline() }
            if phase == "exited" || phase == "failed" { terminalEvent = phase }
            else { state = phase }
        }
    }

    public func send(_ command: String, values: [String: Any] = [:]) {
        guard active, let sessionID else { return }
        var message = values
        message["protocol"] = 1; message["session"] = sessionID; message["command"] = command
        do {
            let bytes = try JSONSerialization.data(withJSONObject: message) + Data([10])
            try commandPipe?.fileHandleForWriting.write(contentsOf: bytes)
        } catch { fail("运行进程的控制通道已断开。") }
    }

    public func togglePause() { send(state == "paused" ? "resume" : "pause") }

    public func setPauseWhenInactive(_ enabled: Bool) {
        send("set-pause-inactive", values: ["enabled": enabled])
    }

    public func stop() {
        guard active, stopping == nil else { return }
        send("stop")
        startStopDeadline()
    }

    private func startStopDeadline() {
        guard stopping == nil, let id = sessionID else { return }
        stopping = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.guestManagedStorage == true ? 30_000_000_000 : 2_000_000_000)
            guard !Task.isCancelled, let self, self.sessionID == id, let child = self.process, child.isRunning else { return }
            self.error = self.error ?? "游戏未及时保存退出，已结束运行进程；之前的存档保留。"
            child.terminate()
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, child.isRunning else { return }
            kill(child.processIdentifier, SIGKILL)
        }
    }

    private func fail(_ reason: String) {
        error = error ?? reason
        startStopDeadline()
        if let child = process, child.isRunning { child.terminate() }
    }

    private func finishIfReaped() {
        guard let exited, stdoutEnded, stderrEnded else { return }
        let success = exited == 0 && !signalExit && checkpointReceived && terminalEvent == "exited" && error == nil
        if !success { error = error ?? "游戏进程意外退出（\(exited)）。资料库仍可使用；之前的存档保留。" }
        state = success ? "exited" : "failed"
        recordTermination(phase: "finished")
        watchdog?.cancel(); watchdog = nil; stopping?.cancel(); stopping = nil
        drainDeadline?.cancel(); drainDeadline = nil
        process?.terminationHandler = nil; process = nil
        closePipes()
    }

    private func recordTermination(phase: String) {
        diagnosticsLog?.record([
            "session": sessionID ?? "", "pid": pid, "runtime": runtime ?? "", "phase": phase, "state": state,
            "startedAt": startDate.timeIntervalSince1970, "recordedAt": Date().timeIntervalSince1970,
            "exitStatus": exited as Any? ?? NSNull(), "terminationReason": exited == nil ? "not-started" : signalExit ? "signal" : "exit",
            "storageClosed": checkpointReceived, "terminalEvent": terminalEvent as Any? ?? NSNull(),
            "stdoutEnded": stdoutEnded, "stderrEnded": stderrEnded, "error": error as Any? ?? NSNull()
        ])
    }

    private func closePipes() {
        readers.forEach { $0.stop() }; readers.removeAll()
        try? commandPipe?.fileHandleForWriting.close()
        try? outputPipe?.fileHandleForReading.close(); try? errorPipe?.fileHandleForReading.close()
        try? eventLog?.close(); diagnosticsLog?.close()
        commandPipe = nil; outputPipe = nil; errorPipe = nil; eventLog = nil; diagnosticsLog = nil
    }

    public func wait(until predicate: @MainActor () -> Bool, timeout: Double = 10) async throws {
        let limit = Date().addingTimeInterval(timeout)
        while !predicate() && Date() < limit { try await Task.sleep(nanoseconds: 20_000_000) }
        guard predicate() else { throw LibraryFailure("等待运行状态超时：\(state) / \(error ?? "无错误消息")") }
    }
}
