// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import Combine
import Darwin

/// Only the Chrome instance launched for this login is connected. Its temporary
/// profile and private pipe never attach to the person's everyday browser.
@MainActor final class GoogleBrowserLogin: ObservableObject {
    @Published private(set) var active = false
    private var task: Task<Void, Never>?
    static var browser: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome")
    }

    func start(completed: @escaping (Result<String, Error>) -> Void) {
        guard !active else { return }
        active = true
        task = Task {
            var child: LoginBrowserProcess?
            var result: Result<String, Error>
            do {
                guard let app = Self.browser, let executable = Bundle(url: app)?.executableURL else {
                    throw PlayError("未找到 Google Chrome，请使用内置登录。")
                }
                let process = try LoginBrowserProcess(executable: executable)
                child = process
                let token = try await process.waitForLogin()
                try Task.checkCancellation()
                result = .success(token)
            } catch { result = .failure(error) }
            // Cleanup must run even when the view's task was cancelled.
            if let child { await Task { await child.close() }.value }
            active = false; task = nil
            if !Task.isCancelled { completed(result) }
        }
    }
    func cancel() { task?.cancel() }
}

@MainActor private final class LoginBrowserProcess {
    private let directory: URL
    private let pid: pid_t
    private let connection: PlayLoginPipe

    init(executable: URL) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("HuskGoogleLogin-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let input = Pipe(), output = Pipe()
        do {
            pid = try Self.spawn(executable: executable, profile: directory, input: input, output: output)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        try? input.fileHandleForReading.close(); try? output.fileHandleForWriting.close()
        connection = PlayLoginPipe(reader: output.fileHandleForReading, writer: input.fileHandleForWriting)
    }

    private static func spawn(executable: URL, profile: URL, input: Pipe, output: Pipe) throws -> pid_t {
        // Chrome reads fd 3 and writes fd 4. Duplicate above those descriptors
        // before mapping them so a pipe's original fd cannot collide with them.
        let inputFD = fcntl(input.fileHandleForReading.fileDescriptor, F_DUPFD_CLOEXEC, 10)
        let outputFD = fcntl(output.fileHandleForWriting.fileDescriptor, F_DUPFD_CLOEXEC, 10)
        defer { if inputFD >= 0 { Darwin.close(inputFD) }; if outputFD >= 0 { Darwin.close(outputFD) } }
        guard inputFD >= 0, outputFD >= 0 else { throw PlayError("无法建立 Google 登录连接。") }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { throw PlayError("无法准备登录窗口。") }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawnattr_init(&attributes) == 0 else { throw PlayError("无法准备登录窗口。") }
        defer { posix_spawnattr_destroy(&attributes) }
        let setup = [
            posix_spawn_file_actions_adddup2(&actions, inputFD, 3),
            posix_spawn_file_actions_adddup2(&actions, outputFD, 4),
            posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0),
            posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0),
            posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0),
            posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))
        ]
        guard setup.allSatisfy({ $0 == 0 }) else { throw PlayError("无法准备登录连接。") }
        let arguments = [executable.path, "--user-data-dir=\(profile.path)", "--remote-debugging-pipe",
                         "--no-first-run", "--no-default-browser-check", "--disable-background-mode",
                         "--disable-sync", "--new-window", GoogleLoginPolicy.url.absoluteString]
        var argv = arguments.map { strdup($0) } + [nil]
        var environment = ProcessInfo.processInfo.environment.filter { $0.key != "CHROME_LOG_FILE" }.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; environment.forEach { free($0) } }
        var child: pid_t = 0
        let status = posix_spawn(&child, executable.path, &actions, &attributes, &argv, &environment)
        guard status == 0 else { throw PlayError("无法打开 Google Chrome（\(status)）。") }
        return child
    }

    func waitForLogin() async throws -> String {
        let deadline = Date().addingTimeInterval(600)
        var poller = GoogleLoginPoller()
        while Date() < deadline {
            try Task.checkCancellation()
            if let token = try await poller.poll(connection) { return token }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw PlayError("Google 登录已超时，请重试。")
    }

    func close() async {
        _ = try? await connection.request("Browser.close", timeout: 2)
        connection.close()
        var status: Int32 = 0
        let deadline = Date().addingTimeInterval(3)
        while waitpid(pid, &status, WNOHANG) == 0 {
            if Date() >= deadline { kill(pid, SIGTERM); break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        // Reap only our child, then remove only its disposable profile. Nothing
        // from a normal Chrome profile or its running processes is inspected.
        while waitpid(pid, &status, WNOHANG) == 0 { try? await Task.sleep(for: .milliseconds(100)) }
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Inspect navigation on every poll, including after a protocol failure. A
/// Google rejection is terminal, not a missing cookie to wait ten minutes for.
/// URLs are used only to classify the page and are never included in errors.
@MainActor struct GoogleLoginPoller {
    private var targetID: String?
    private var session: String?

    private func pages(_ connection: PlayLoginPipe) async throws -> [[String: Any]] {
        let reply = try await connection.request("Target.getTargets")
        let pages = (reply["targetInfos"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == "page" }
        if pages.contains(where: {
            ($0["url"] as? String).flatMap(URL.init(string:)).map(GoogleLoginPolicy.isRejection) == true
        }) { throw GoogleLoginFailure.browserRejected }
        return pages
    }

    mutating func poll(_ connection: PlayLoginPipe) async throws -> String? {
        let pages = try await self.pages(connection).filter {
            ($0["url"] as? String).flatMap(URL.init(string:)).map(GoogleLoginPolicy.allows) == true
        }
        guard let target = (pages.first { $0["targetId"] as? String == targetID } ?? pages.first)?["targetId"] as? String else {
            targetID = nil; session = nil; return nil
        }
        if target != targetID || session == nil {
            let attached = try await connection.request("Target.attachToTarget", parameters: ["targetId": target, "flatten": true])
            targetID = target; session = attached["sessionId"] as? String
        }
        guard let session else { return nil }
        let reply: [String: Any]
        do {
            reply = try await connection.request("Network.getCookies", parameters: ["urls": [GoogleLoginPolicy.url.absoluteString]], session: session)
        } catch {
            // A navigation can replace the renderer while cookies are being
            // requested. Prefer Google's actual rejection over a pipe error.
            _ = try await self.pages(connection)
            throw error
        }
        guard let raw = reply["cookies"], JSONSerialization.isValidJSONObject(raw) else { return nil }
        let cookies = try JSONDecoder().decode([GoogleLoginPolicy.Cookie].self, from: JSONSerialization.data(withJSONObject: raw))
        return GoogleLoginPolicy.token(in: cookies)
    }
}

/// A bounded, cancellation-aware transport for Chrome's private NUL-delimited
/// pipe. Protocol payloads (including the temporary cookie) are never logged.
@MainActor final class PlayLoginPipe {
    private let reader: FileHandle
    private let writer: FileHandle
    private var bytes = Data()
    private var nextID = 0
    private var closed = false
    private struct Pending {
        let continuation: CheckedContinuation<[String: Any], Error>
        let timeout: Task<Void, Never>
    }
    private var pending: [Int: Pending] = [:]

    init(reader: FileHandle, writer: FileHandle) {
        self.reader = reader; self.writer = writer
        reader.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor [weak self] in self?.receive(data) }
        }
    }
    func request(_ method: String, parameters: [String: Any] = [:], session: String? = nil,
                 timeout: TimeInterval = 10) async throws -> [String: Any] {
        try Task.checkCancellation()
        guard !closed else { throw PlayError("Google 登录窗口已关闭。") }
        nextID += 1; let id = nextID
        var message: [String: Any] = ["id": id, "method": method, "params": parameters]
        if let session { message["sessionId"] = session }
        var packet = try JSONSerialization.data(withJSONObject: message); packet.append(0)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timer = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                    self?.finish(id, .failure(PlayError("Google 登录窗口没有响应，请重试。")))
                }
                pending[id] = Pending(continuation: continuation, timeout: timer)
                do { try writer.write(contentsOf: packet) }
                catch { close() }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(id, .failure(CancellationError())) }
        }
    }
    private func receive(_ data: Data) {
        guard !closed else { return }
        guard !data.isEmpty, bytes.count + data.count <= 1 << 20 else { close(); return }
        bytes.append(data)
        while let end = bytes.firstIndex(of: 0) {
            let packet = bytes.subdata(in: bytes.startIndex..<end)
            bytes.removeSubrange(bytes.startIndex...end)
            guard let reply = (try? JSONSerialization.jsonObject(with: packet)) as? [String: Any] else { close(); return }
            guard let id = reply["id"] as? Int else { continue }
            if let result = reply["result"] as? [String: Any] { finish(id, .success(result)) }
            else { finish(id, .failure(PlayError("Google 登录连接中断，请重新打开登录窗口。"))) }
        }
    }
    private func finish(_ id: Int, _ result: Result<[String: Any], Error>) {
        guard let item = pending.removeValue(forKey: id) else { return }
        item.timeout.cancel(); item.continuation.resume(with: result)
    }
    func close() {
        guard !closed else { return }; closed = true
        reader.readabilityHandler = nil; try? reader.close(); try? writer.close()
        bytes.removeAll()
        for id in Array(pending.keys) { finish(id, .failure(PlayError("Google 登录窗口已关闭。"))) }
    }
}
