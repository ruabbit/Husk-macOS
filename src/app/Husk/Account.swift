// SPDX-License-Identifier: GPL-2.0-or-later
// A Husk account on the website (itslevii.dev): sign in, the profile (avatar, name, @handle, games, apps, playtime, recently
// played, achievements), and the library it shows, sent from here. The session token lives in the Keychain.
import Foundation
import Security
import SwiftUI
#if os(macOS)
import AppKit
typealias AccountImage = NSImage
#else
import UIKit
typealias AccountImage = UIImage
#endif

// MARK: - what the site answers

struct HuskUser: Codable, Equatable {
    struct Stats: Codable, Equatable { var games: Int; var apps: Int; var playtimeSeconds: Double }
    struct Played: Codable, Equatable, Identifiable {
        var package: String
        var name: String
        var platform: String
        var type: String
        var playtimeSeconds: Double
        var lastPlayed: String?
        var id: String { package }
    }
    struct Achievement: Codable, Equatable, Identifiable {
        var id: String
        var title: String
        var detail: String
        var unlockedAt: String?
        var unlocked: Bool
    }
    var id: String
    var username: String
    var displayName: String
    var avatarUrl: String?
    var createdAt: String
    var stats: Stats
    var recent: [Played]
    var achievements: [Achievement]
}

private struct AuthAnswer: Codable { var token: String; var user: HuskUser }
private struct SiteError: Codable { var error: String }

struct AccountError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - playtime

/// How long each game has been played from Husk, kept on this iPhone: a session starts when its screen appears and is
/// counted when it goes.
@MainActor enum Playtime {
    private static let key = "husk.playtime"
    private static var started: [String: Date] = [:]

    static var all: [String: Double] { UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:] }
    static func seconds(_ id: String) -> Double { all[id] ?? 0 }

    static func begin(_ id: String) { started[id] = Date() }
    static func end(_ id: String) {
        guard let s = started.removeValue(forKey: id) else { return }
        let add = Date().timeIntervalSince(s)
        guard add > 2, add < 24 * 3600 else { return }
        var d = all
        d[id, default: 0] += add
        UserDefaults.standard.set(d, forKey: key)
        Account.shared.librarySoon()
    }

    /// "3h 42m", "12m", "0m".
    static func text(_ seconds: Double) -> String {
        let m = Int(seconds / 60), h = m / 60
        return h > 0 ? "\(h)h \(m % 60)m" : "\(m)m"
    }
}

// MARK: - the account

@MainActor final class Account: ObservableObject {
    static let shared = Account()

    @Published private(set) var user: HuskUser?
    @Published private(set) var avatar: AccountImage?
    @Published var busy = false

    var signedIn: Bool { token != nil }

    private static let userKey = "husk.account.user"
    private var token: String? { readToken() }
    private let session: URLSession
    private let sites: [URL]
    private let defaults: UserDefaults
    private let avatarFile: URL
    private let readToken: () -> String?
    private let writeToken: (String) throws -> Void
    private let deleteToken: () -> Void
    @Published private(set) var error: String?
    // macOS supplies its own repository rows; the web protocol is shared.
    var libraryRows: (() -> [[String: Any]])?
    private var syncTask: Task<Void, Never>?

    init(session: URLSession = .shared, sites: [URL]? = nil,
         defaults: UserDefaults = .standard, avatarFile: URL? = nil,
         readToken: @escaping () -> String? = { Keychain.read() },
         writeToken: @escaping (String) throws -> Void = { try Keychain.write($0) },
         deleteToken: @escaping () -> Void = { Keychain.delete() }) {
        self.session = session; self.sites = sites ?? CompatibilityStore.sites; self.defaults = defaults
        self.readToken = readToken; self.writeToken = writeToken; self.deleteToken = deleteToken
        #if os(macOS)
        let avatarPath = "Husk/account-avatar.png"
        #else
        let avatarPath = "account-avatar.png"
        #endif
        self.avatarFile = avatarFile ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(avatarPath)
        if readToken() != nil, let d = defaults.data(forKey: Self.userKey), let u = try? JSONDecoder().decode(HuskUser.self, from: d) { user = u }
        if user != nil, let d = try? Data(contentsOf: self.avatarFile) { avatar = AccountImage(data: d) }
    }

    // MARK: talking to the site

    private func call(_ method: String, _ path: String, body: [String: Any]? = nil, auth: Bool = true) async throws -> Data {
        var last: Error = AccountError(message: "The Husk website did not answer.")
        for site in sites {
            var r = URLRequest(url: site.appendingPathComponent(path))
            r.httpMethod = method
            r.timeoutInterval = 20
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if auth, let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            if let body { r.httpBody = try JSONSerialization.data(withJSONObject: body) }
            do {
                let (data, resp) = try await session.data(for: r)
                guard let http = resp as? HTTPURLResponse else { continue }
                if http.statusCode >= 500 { last = AccountError(message: "The Husk website had a problem (\(http.statusCode))."); continue }
                if http.statusCode == 401, auth { forget() }
                if http.statusCode >= 400 {
                    let msg = (try? JSONDecoder().decode(SiteError.self, from: data))?.error ?? "Something went wrong (\(http.statusCode))."
                    throw AccountError(message: msg)
                }
                return data
            } catch let e as AccountError {
                throw e
            } catch {
                last = error
            }
        }
        throw last
    }

    private func take(_ u: HuskUser) {
        user = u
        if let d = try? JSONEncoder().encode(u) { defaults.set(d, forKey: Self.userKey) }
        Task { await loadAvatar() }
    }

    private func loadAvatar() async {
        guard let u = user, let s = u.avatarUrl else { avatar = nil; try? FileManager.default.removeItem(at: avatarFile); return }
        guard let site = sites.first, let url = URL(string: s, relativeTo: site) else { return }
        guard let (d, _) = try? await session.data(from: url), let img = AccountImage(data: d) else { return }
        guard user?.id == u.id, user?.avatarUrl == s else { return }
        avatar = img
        try? FileManager.default.createDirectory(at: avatarFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? d.write(to: avatarFile, options: .atomic)
    }

    private func forget() {
        syncTask?.cancel(); syncTask = nil
        deleteToken()
        user = nil
        avatar = nil
        defaults.removeObject(forKey: Self.userKey)
        try? FileManager.default.removeItem(at: avatarFile)
    }

    // MARK: what the screens do

    func signUp(username: String, password: String, displayName: String) async throws {
        busy = true; defer { busy = false }
        let d = try await call("POST", "api/auth/signup", body: ["username": username, "password": password, "displayName": displayName], auth: false)
        let a = try JSONDecoder().decode(AuthAnswer.self, from: d)
        try writeToken(a.token)
        take(a.user)
        await syncLibrary()
    }

    func signIn(username: String, password: String) async throws {
        busy = true; defer { busy = false }
        let d = try await call("POST", "api/auth/login", body: ["username": username, "password": password], auth: false)
        let a = try JSONDecoder().decode(AuthAnswer.self, from: d)
        try writeToken(a.token)
        take(a.user)
        await syncLibrary()
    }

    func signOut() async {
        _ = try? await call("POST", "api/auth/logout")
        forget()
    }

    func refresh() async {
        guard let sessionToken = token else { return }
        do {
            let d = try await call("GET", "api/me")
            guard token == sessionToken else { return }
            take(try JSONDecoder().decode(HuskUser.self, from: d)); error = nil
        } catch { self.error = error.localizedDescription }
    }

    func update(displayName: String? = nil, avatarPNG: Data?? = nil) async throws {
        var body: [String: Any] = [:]
        if let displayName { body["displayName"] = displayName }
        if let avatarPNG { body["avatarPng"] = avatarPNG.map { $0.base64EncodedString() } ?? NSNull() }
        busy = true; defer { busy = false }
        let d = try await call("PATCH", "api/me", body: body)
        take(try JSONDecoder().decode(HuskUser.self, from: d))
    }

    /// The library, a moment after something changed (a session ended), so several changes go as one.
    func librarySoon() {
        guard signedIn else { return }
        syncTask?.cancel()
        syncTask = Task { try? await Task.sleep(nanoseconds: 3_000_000_000); if !Task.isCancelled { await syncLibrary() } }
    }

    /// Every game and app here, with its playtime and when it was last played, replaces what the account had.
    func syncLibrary() async {
        guard signedIn else { return }
        let sessionToken = token
        #if os(macOS)
        guard let libraryRows else { return }
        let rows = Array(libraryRows().prefix(2000))
        #else
        let iso = ISO8601DateFormatter()
        let items = Launcher.items(store: TranslationLayerStore.shared, host: AndroidHost.shared).filter { $0 != .android }
        let rows: [[String: Any]] = items.prefix(2000).compactMap { i in
            guard let id = i.accountID else { return nil }
            return ["package": id, "name": String(i.title.prefix(80)), "platform": i.isPS4 ? "ps4" : "android",
             "type": i.isGame ? "game" : "app", "playtimeSeconds": Playtime.seconds(i.id).rounded(),
             "lastPlayed": i.lastUsed.map { iso.string(from: $0) } ?? NSNull()]
        }
        #endif
        do {
            let d = try await call("PUT", "api/me/library", body: ["items": rows])
            guard token == sessionToken, !Task.isCancelled else { return }
            take(try JSONDecoder().decode(HuskUser.self, from: d)); error = nil
        } catch { self.error = error.localizedDescription }
    }

    /// The avatar picked for the profile, made small and square before it goes.
    static func avatarPNG(_ image: AccountImage) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let side: CGFloat = 256
        #if os(macOS)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        let k = max(side / image.size.width, side / image.size.height)
        let w = image.size.width * k, h = image.size.height * k
        image.draw(in: NSRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h),
                   from: .zero, operation: .copy, fraction: 1)
        return bitmap.representation(using: .png, properties: [:])
        #else
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt).image { _ in
            let s = image.size, k = max(side / s.width, side / s.height)
            let w = s.width * k, h = s.height * k
            image.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        }
        return img.pngData()
        #endif
    }
}

#if !os(macOS)
extension LibraryItem {
    /// What the account knows it by: the Android package, or a PS4 game's title ID.
    var accountID: String? {
        if case .ps4(let g) = self { return g.titleID }
        return packageName
    }
}

#endif

// MARK: - Keychain

private enum Keychain {
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                               kSecAttrService as String: "com.husk.account",
                                               kSecAttrAccount as String: "session"]
    static func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func write(_ token: String) throws {
        let value = Data(token.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = value
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AccountError(message: "Could not save the account session in Keychain.") }
    }
    static func delete() { SecItemDelete(query as CFDictionary) }
}

// MARK: - the avatar

/// The account's picture, or a person in a circle when there is none.
struct AccountAvatar: View {
    var size: CGFloat = 36
    @ObservedObject private var account = Account.shared

    var body: some View {
        Group {
            if let img = account.avatar {
                #if os(macOS)
                Image(nsImage: img).resizable().scaledToFill()
                #else
                Image(uiImage: img).resizable().scaledToFill()
                #endif
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    #if os(macOS)
                    .background(Color(nsColor: .controlBackgroundColor))
                    #else
                    .background(Console.raised)
                    #endif
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
    }
}
