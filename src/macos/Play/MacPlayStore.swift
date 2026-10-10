// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Combine
import SharedLibrary

protocol MacPlayService {
    func signIn(email: String?, token: String?) async throws -> PlaySession
    func refresh(_ session: PlaySession) async throws -> PlaySession
    func browse(_ session: PlaySession) async throws -> [PlayAPI.PlayApp]
    func search(_ query: String, session: PlaySession) async throws -> [PlayAPI.PlayApp]
    func details(_ package: String, session: PlaySession) async throws -> PlayAPI.PlayApp
    func download(_ app: PlayAPI.PlayApp, session: PlaySession,
                  progress: @escaping @MainActor @Sendable (Double) -> Void) async throws -> PlayDownloadedFiles
}

struct GooglePlayService: MacPlayService {
    func signIn(email: String?, token: String?) async throws -> PlaySession {
        guard let email, let token else { return try await PlayAPI.fetchAuroraGuestSession() }
        var session = PlaySession(email: email, aasToken: try await PlayAPI.accountToken(email: email, oauthToken: token))
        (session.gsfID, session.consistencyToken) = try await PlayAPI.checkin()
        session.bearer = try await PlayAPI.playToken(session)
        session.deviceConfigToken = try await PlayAPI.uploadDeviceConfig(session)
        return session
    }
    func refresh(_ session: PlaySession) async throws -> PlaySession {
        if session.isAnonymous { return try await PlayAPI.fetchAuroraGuestSession() }
        var session = session; session.bearer = try await PlayAPI.playToken(session); return session
    }
    func browse(_ session: PlaySession) async throws -> [PlayAPI.PlayApp] { try await PlayAPI.browse(session: session) }
    func search(_ query: String, session: PlaySession) async throws -> [PlayAPI.PlayApp] { try await PlayAPI.search(query: query, session: session) }
    func details(_ package: String, session: PlaySession) async throws -> PlayAPI.PlayApp {
        guard let app = try await PlayAPI.details(packageName: package, session: session), app.id == package else {
            throw PlayError("未取得此应用的详情，请稍后重试。")
        }
        return app
    }
    func download(_ app: PlayAPI.PlayApp, session: PlaySession,
                  progress: @escaping @MainActor @Sendable (Double) -> Void) async throws -> PlayDownloadedFiles {
        guard app.versionCode > 0 else { throw PlayError("Play 未返回可下载的应用版本。") }
        var token: String?
        // Paid apps use the account's existing entitlement. Never issue a purchase.
        if app.isFree { token = try await PlayAPI.purchase(packageName: app.id, versionCode: app.versionCode, session: session) }
        let delivery = try await PlayAPI.delivery(packageName: app.id, versionCode: app.versionCode, deliveryToken: token, session: session)
        return try await PlayDownload().fetch(delivery, progress: progress)
    }
}

@MainActor final class MacPlayStore: ObservableObject {
    struct DownloadState {
        var progress: Double = 0
        var phase = "准备下载…"
        var error: String?
        var gameID: String?
        var active: Bool = true
        var cancellable: Bool = true
    }
    @Published private(set) var session: PlaySession?
    @Published private(set) var busy = false
    @Published private(set) var searching = false
    @Published private(set) var apps: [PlayAPI.PlayApp] = []
    @Published var error: String?
    @Published private(set) var downloads: [String: DownloadState] = [:]
    private let service: MacPlayService
    private let credentials: PlaySessionStorage
    private var generation = UUID()
    private var queryID = UUID()
    private var restored = false
    private var loginTask: Task<Void, Never>?
    private var jobs: [String: Task<Void, Never>] = [:]
    var hasActiveDownloads: Bool { downloads.values.contains(where: \.active) }

    init(service: MacPlayService = GooglePlayService(), credentials: PlaySessionStorage = PlayCredentials()) {
        self.service = service; self.credentials = credentials
    }
    func restore() async {
        guard !restored else { return }; restored = true
        let id = generation
        do {
            if let saved = try credentials.load() {
                let fresh = try await service.refresh(saved)
                guard generation == id, !Task.isCancelled else { return }
                try credentials.save(fresh); session = fresh
            }
        } catch { if generation == id, !Task.isCancelled { self.error = "恢复 Play 登录失败：\(error.localizedDescription)" } }
    }
    func connect(email: String? = nil, token: String? = nil) {
        loginTask?.cancel(); generation = UUID(); let id = generation
        busy = true; error = nil
        loginTask = Task {
            defer { if generation == id { busy = false; loginTask = nil } }
            do {
                let fresh = try await service.signIn(email: email, token: token)
                try Task.checkCancellation(); guard generation == id else { return }
                try credentials.save(fresh); session = fresh
            } catch { if generation == id, !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    func cancelLogin() { loginTask?.cancel(); loginTask = nil; busy = false; generation = UUID() }
    func signOut() {
        cancelLogin(); jobs.values.forEach { $0.cancel() }; jobs.removeAll()
        session = nil; apps = []; searching = false; downloads = [:]; error = nil
        do { try credentials.remove() } catch { self.error = error.localizedDescription }
    }
    func authenticated<T>(_ operation: (PlaySession) async throws -> T) async throws -> T {
        guard let original = session else { throw PlayError("请先登录 Google Play。") }
        let id = generation
        do { return try await operation(original) }
        catch let error as PlayError where error.httpStatus == 401 {
            try Task.checkCancellation()
            guard id == generation else { throw CancellationError() }
            let fresh = try await service.refresh(original)
            try Task.checkCancellation(); guard id == generation else { throw CancellationError() }
            try credentials.save(fresh); session = fresh
            return try await operation(fresh)
        }
    }
    func load(query: String) async {
        guard session != nil else { return }
        let id = UUID(), account = generation; queryID = id; searching = true; error = nil
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { if queryID == id, account == generation { searching = false } }
        do {
            let result = try await authenticated { s in
                try await query.isEmpty ? service.browse(s) : service.search(query, session: s)
            }
            try Task.checkCancellation(); guard queryID == id, account == generation else { return }
            apps = result
        } catch { if !Task.isCancelled, queryID == id, account == generation { apps = []; self.error = error.localizedDescription } }
    }
    func details(_ package: String) async throws -> PlayAPI.PlayApp {
        try await authenticated { try await service.details(package, session: $0) }
    }
    func install(_ app: PlayAPI.PlayApp, importer: @escaping @MainActor ([URL], PlayAPI.PlayApp) async throws -> LibraryGame) {
        guard jobs[app.id] == nil, session != nil else { return }
        let account = generation
        downloads[app.id] = DownloadState()
        jobs[app.id] = Task { [self] in
            defer { if account == generation { jobs.removeValue(forKey: app.id) } }
            do {
                let fresh = try await details(app.id)
                let files = try await authenticated { s in
                    try await service.download(fresh, session: s) { [weak self] progress in
                        guard let self, self.generation == account, self.downloads[app.id]?.cancellable == true else { return }
                        self.downloads[app.id]?.progress = progress; self.downloads[app.id]?.phase = "正在下载"
                    }
                }
                defer { files.remove() }
                try Task.checkCancellation(); guard generation == account else { return }
                downloads[app.id]?.phase = "校验并导入…"; downloads[app.id]?.cancellable = false
                let game = try await importer(files.apks, fresh)
                guard generation == account else { return }
                downloads[app.id] = DownloadState(progress: 1, phase: "已加入资料库", gameID: game.id, active: false, cancellable: false)
            } catch {
                guard generation == account else { return }
                downloads[app.id] = DownloadState(phase: Task.isCancelled ? "已取消" : "下载失败",
                    error: Task.isCancelled ? nil : error.localizedDescription, active: false, cancellable: false)
            }
        }
    }
    func cancel(_ package: String) { if downloads[package]?.cancellable == true { jobs[package]?.cancel() } }
    func stopDownloads() { jobs.values.forEach { $0.cancel() } }
}
