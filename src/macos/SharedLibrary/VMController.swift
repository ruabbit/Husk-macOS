// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Combine
import CryptoKit
import Darwin

/// The library owns a separate VM process. QEMU and its permissions never enter
/// the SwiftUI process. A running VM owns its disk lock until the child is reaped.
@MainActor public final class VMController: ObservableObject {
    @Published public private(set) var state = "idle"
    @Published public private(set) var detail = ""
    @Published public private(set) var error: String?
    @Published public private(set) var latest: [String: Any] = [:]
    public private(set) var pid: Int32 = 0
    public private(set) var sessionID: String?
    public var active: Bool { process != nil }
    public var ready: Bool { latest["booted"] as? Bool == true || state == "running" || state == "paused" }
    private var process: Process?
    private var input: Pipe?
    private var pipes: [Pipe] = []
    private var readers: [PipeReader] = []
    private var events: FileHandle?
    private var diagnostics: FileHandle?
    private var buffer = Data()
    private var eventSequence = 0
    private var requestSequence = 0
    private var replies: [Int: [String: Any]] = [:]
    private var cleanShutdown = false
    private var lastEvent = Date()
    private var watchdog: Task<Void, Never>?
    private var shutdownTask: Task<Void, Never>?

    public init() { signal(SIGPIPE, SIG_IGN) }
    public static func helper(in bundle: URL) -> URL {
        bundle.appendingPathComponent("Contents/Helpers/VMRunner.app/Contents/MacOS/VMRunner")
    }
    public static func available(in bundle: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: helper(in: bundle).path)
    }
    public func start(executable: URL, guest: URL, logs: URL, accelerator: String = "tcg",
                      graphics: String = "virgl", headless: Bool = false, muted: Bool = false,
                      automation: Bool = false, maxRunSeconds: Int = 0) throws {
        guard !active else { throw LibraryFailure("Android 虚拟机正在运行。") }
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 else {
            throw LibraryFailure("此开发版本的 Android 运行库需要 macOS 27 或更新版本。")
        }
        guard ["tcg", "hvf"].contains(accelerator), ["virgl", "software"].contains(graphics) else {
            throw LibraryFailure("无效的虚拟机配置。")
        }
        guard FileManager.default.fileExists(atPath: guest.appendingPathComponent("guest.json").path) else {
            throw LibraryFailure("请选择已准备好的 Android 数据目录，目录中应包含 guest.json。")
        }
        let id = UUID().uuidString, directory = logs.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration: [String: Any] = ["session": id, "guest": guest.path, "accelerator": accelerator,
            "graphics": graphics, "memoryMiB": 4096, "cpus": 4, "width": 960, "height": 540,
            "showWindow": !headless, "muted": muted || headless,
            "automation": automation, "maxRunSeconds": maxRunSeconds]
        let configURL = directory.appendingPathComponent("config.json")
        try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted, .sortedKeys]).write(to: configURL)
        let eventURL = directory.appendingPathComponent("events.jsonl"), errorURL = directory.appendingPathComponent("stderr.log")
        try Data().write(to: eventURL); try Data().write(to: errorURL)
        events = try FileHandle(forWritingTo: eventURL); diagnostics = try FileHandle(forWritingTo: errorURL)
        let child = Process(), command = Pipe(), output = Pipe(), errors = Pipe()
        child.executableURL = executable; child.arguments = ["--config", configURL.path]
        child.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "TMPDIR": NSTemporaryDirectory()]
        child.standardInput = command; child.standardOutput = output; child.standardError = errors
        process = child; input = command; pipes = [output, errors]
        shutdownTask?.cancel(); shutdownTask = nil
        watchdog?.cancel(); watchdog = nil
        sessionID = id; state = "starting"; error = nil; detail = "Android 正在冷启动…"
        eventSequence = 0; requestSequence = 0; replies = [:]; latest = [:]; buffer = Data(); cleanShutdown = false; lastEvent = Date()
        child.terminationHandler = { [weak self] child in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard let self, self.sessionID == id else { return }
                let clean = child.terminationStatus == 0 && self.cleanShutdown
                self.state = clean ? "exited" : "failed"
                self.detail = clean ? "Android 已关闭，磁盘已释放。" : "Android 意外结束；下次启动将从磁盘恢复。"
                if !clean { self.error = self.error ?? "VMRunner 退出码 \(child.terminationStatus)，请查看日志。" }
                self.process = nil; self.pid = 0; self.watchdog?.cancel(); self.shutdownTask?.cancel()
                self.watchdog = nil; self.shutdownTask = nil
                self.readers.forEach { $0.stop() }; self.readers.removeAll()
                try? self.input?.fileHandleForWriting.close(); self.input = nil; self.pipes.removeAll()
                try? self.events?.close(); try? self.diagnostics?.close(); self.events = nil; self.diagnostics = nil
            }
        }
        do { try child.run() } catch {
            process = nil; input = nil; pipes = []; self.error = error.localizedDescription; state = "failed"
            try? events?.close(); try? diagnostics?.close(); throw error
        }
        pid = child.processIdentifier
        try? command.fileHandleForReading.close(); try? output.fileHandleForWriting.close(); try? errors.fileHandleForWriting.close()
        for (handle, isError) in [(output.fileHandleForReading, false), (errors.fileHandleForReading, true)] {
            let reader = PipeReader(); readers.append(reader)
            reader.read(handle) { [weak self] data in
                DispatchQueue.main.async {
                    guard let self, self.sessionID == id, self.active, !data.isEmpty else { return }
                    if isError { try? self.diagnostics?.write(contentsOf: data) }
                    else { self.consume(data) }
                }
            }
        }
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled, self.active else { return }
                if Date().timeIntervalSince(self.lastEvent) > 30 { self.error = "VMRunner 没有响应。"; self.stop(); return }
            }
        }
    }
    private func consume(_ data: Data) {
        buffer.append(data)
        guard buffer.count <= 3 << 20 else { error = "VMRunner 消息过长。"; stop(); return }
        while let end = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
            guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  event["session"] as? String == sessionID, event["protocol"] as? Int == 1,
                  event["pid"] as? Int32 == pid, let seq = event["seq"] as? Int, seq == eventSequence + 1 else {
                error = "VMRunner 返回了无效的会话消息。"; stop(); return
            }
            eventSequence = seq; lastEvent = Date(); latest = event
            try? events?.write(contentsOf: line + Data([10]))
            if let phase = event["state"] as? String { state = phase }
            switch event["event"] as? String {
            case "android-ready": detail = "Android 已就绪。"
            case "installing": detail = "正在安装 APK…"
            case "storage-closed": cleanShutdown = event["clean"] as? Bool == true
            case "failure", "shutdown-timeout": error = event["detail"] as? String
            case "command-result", "command-error": if let id = event["id"] as? Int { replies[id] = event }
            default: break
            }
        }
    }
    @discardableResult public func send(_ command: String, values: [String: Any] = [:]) throws -> Int {
        guard let input, let sessionID, active else { throw LibraryFailure("Android 未运行。") }
        requestSequence += 1
        var message = values; message["command"] = command; message["session"] = sessionID; message["id"] = requestSequence
        let data = try JSONSerialization.data(withJSONObject: message) + Data([10])
        try input.fileHandleForWriting.write(contentsOf: data)
        return requestSequence
    }
    public func request(_ command: String, values: [String: Any] = [:], timeout: TimeInterval = 20) async throws -> [String: Any] {
        let id = try send(command, values: values), session = sessionID, deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let reply = replies.removeValue(forKey: id) {
                if reply["event"] as? String == "command-error" { throw LibraryFailure(reply["detail"] as? String ?? "Android 操作失败。") }
                return reply["result"] as? [String: Any] ?? [:]
            }
            guard active, sessionID == session else { throw LibraryFailure("Android 会话已经结束。") }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw LibraryFailure("Android 操作超时；未自动重试。")
    }
    public func waitUntilReady(timeout: TimeInterval = 920) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !ready {
            guard active, Date() < deadline else { throw LibraryFailure(error ?? "Android 尚未就绪。") }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
    }
    public func install(apk: URL, sha256: String, package: String) async throws {
        try await waitUntilReady()
        let result = try await request("install", values: ["apk": apk.path, "sha256": sha256], timeout: 4200)
        guard result["status"] as? Int == 0, (result["output"] as? String)?.contains("Success") == true else {
            throw LibraryFailure(result["output"] as? String ?? "APK 安装失败。")
        }
        let launch = try await request("launch", values: ["package": package], timeout: 60)
        guard launch["status"] as? Int == 0 else { throw LibraryFailure(launch["output"] as? String ?? "Android 应用启动失败。") }
        detail = "应用已在 Android 中启动。"
    }
    public func togglePause() { _ = try? send(state == "paused" ? "resume" : "pause") }
    public func stop() {
        guard active, shutdownTask == nil else { return }
        _ = try? send("shutdown"); state = "stopping"; detail = "正在关闭 Android…"
        shutdownTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 55_000_000_000)
            guard !Task.isCancelled, let self, let process = self.process, process.isRunning else { return }
            self.error = "Android 关闭超时；磁盘可能需要恢复。"; process.terminate()
        }
    }
}
