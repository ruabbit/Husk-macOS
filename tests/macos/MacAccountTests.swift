// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import AppKit
import SharedLibrary

private final class AccountHTTP: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    static var requests: [URLRequest] = []
    static var expired = false
    static var maintenance = false
    static var queued = false
    static var library: [String: Any]?
    static let user: [String: Any] = ["id":"fixture", "username":"fixture", "displayName":"Fixture", "createdAt":"2026-10-27",
        "stats":["games":1,"apps":0,"playtimeSeconds":180], "recent":[], "achievements":[]]
    override class func canInit(with request: URLRequest) -> Bool { true } // intercept every URL; never contacts a server
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); defer { Self.lock.unlock() }
        Self.requests.append(request)
        var status = 200
        var body: [String: Any] = Self.user
        if Self.maintenance { status = 503; body = ["maintenance":true] }
        else if request.url!.host == "unavailable.invalid" { status = 503; body = ["error":"unavailable"] }
        else if Self.expired { status = 401; body = ["error":"expired"] }
        else if request.url!.path.contains("/auth/login") || request.url!.path.contains("/auth/signup") { body = ["token":"fixture-only", "user":Self.user] }
        else if Self.queued && request.httpMethod == "PATCH" { status = 202; body = ["queued":true] }
        if request.httpMethod == "PUT" && status == 200 {
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }; var bytes = [UInt8](repeating:0,count:1024)
                while true { let n = stream.read(&bytes,maxLength:bytes.count); if n <= 0 { break }; data.append(contentsOf:bytes.prefix(n)) }
            }
            Self.library = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
        }
        let response = HTTPURLResponse(url:request.url!, statusCode:status, httpVersion:"HTTP/1.1", headerFields:["Content-Type":"application/json"])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:try! JSONSerialization.data(withJSONObject:body))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct AccountTests {
    @MainActor static func main() async {
        do { try await run() } catch { print(error.localizedDescription); exit(1) }
    }
    @MainActor static func run() async throws {
        func check(_ value: Bool, _ message: String) throws {
            guard value else { throw AccountError(message:"FAIL " + message) }; print("PASS " + message)
        }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AccountHTTP.self]
        let session = URLSession(configuration: config)
        let suite = "org.husk.account.fixture." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { defaults.removePersistentDomain(forName:suite); try? FileManager.default.removeItem(at:root); session.invalidateAndCancel() }
        var token: String?
        let sites = [URL(string:"https://unavailable.invalid")!,URL(string:"https://account.invalid")!]
        let account = Account(session:session,sites:sites,defaults:defaults,avatarFile:root.appendingPathComponent("avatar.png"),
            readToken:{token},writeToken:{token=$0},deleteToken:{token=nil})
        let json = #"{"id":"local-id","title":"Game","importedAt":0,"sourceName":"base.apk","apkNames":["base.apk"],"digest":"none","engine":"Godot","abis":["arm64-v8a"],"settings":{},"packageName":"org.husk.fixture"}"#
        let game = try JSONDecoder().decode(LibraryGame.self,from:Data(json.utf8))
        account.libraryRows = { MacAccountLibrary.rows([game],seconds:{_ in 182.6}) }
        try await account.signIn(username:"fixture",password:"fixture-only")
        try check(account.signedIn && account.user?.username == "fixture", "shared account login with service fallback and injected token storage")
        let items = AccountHTTP.library?["items"] as? [[String:Any]]
        try check(items?.first?["package"] as? String == game.packageName && items?.first?["playtimeSeconds"] as? Int == 183 && items?.first?["type"] as? String == "game", "Mac library uploads package identity, rounded playtime and kind")
        try check(AccountHTTP.requests.filter{$0.httpMethod == "PUT"}.allSatisfy{$0.value(forHTTPHeaderField:"Authorization") == "Bearer fixture-only"}, "authenticated library protocol")
        try await account.update(displayName:"New name")
        let before = AccountHTTP.requests.count
        AccountHTTP.maintenance = true
        await account.refresh()
        try check(AccountHTTP.requests.count == before + 1 && account.signedIn && account.error == CompatibilityStore.maintenanceMessage,
                  "account maintenance preserves the session and never falls back")
        AccountHTTP.maintenance = false; AccountHTTP.queued = true
        try await account.update(displayName:"Queued name")
        try check(account.updateQueued && account.user?.displayName == "Queued name", "profile changes retain a visible queued state")
        AccountHTTP.queued = false
        try await account.update(displayName:"New name")
        try check(!account.updateQueued, "ordinary profile update clears the queued state")
        let restored = Account(session:session,sites:sites,defaults:defaults,avatarFile:root.appendingPathComponent("avatar.png"),readToken:{token},writeToken:{token=$0},deleteToken:{token=nil})
        try check(restored.user == account.user, "cached profile reopens only with an existing session")
        let picture = NSImage(size:NSSize(width:800,height:400),flipped:false) { bounds in NSColor.red.setFill(); bounds.fill(); return true }
        let png = Account.avatarPNG(picture)!
        let bitmap = NSBitmapImageRep(data:png)!
        try check(bitmap.pixelsWide == 256 && bitmap.pixelsHigh == 256, "AppKit avatar crop produces a 256 pixel PNG")
        try await account.update(avatarPNG:.some(png)); try await account.update(avatarPNG:.some(nil))
        await account.signOut()
        try check(!account.signedIn && account.user == nil && defaults.data(forKey:"husk.account.user") == nil, "logout removes the session and cached identity")
        try await account.signUp(username:"fixture",password:"fixture-only",displayName:"Fixture")
        AccountHTTP.expired = true; await account.refresh()
        try check(!account.signedIn && account.user == nil, "HTTP 401 invalidates the cached session")
        AccountHTTP.expired = false
        let failed = Account(session:session,sites:sites,defaults:defaults,avatarFile:root.appendingPathComponent("other.png"),readToken:{nil},writeToken:{_ in throw AccountError(message:"fixture storage failure")},deleteToken:{})
        do { try await failed.signIn(username:"fixture",password:"fixture-only"); throw AccountError(message:"FAIL accepted a missing credential") }
        catch { try check(failed.user == nil && !failed.signedIn, "credential persistence failure does not publish a signed-in identity") }
        for language in ["en","zh-Hans"] {
            AppLanguage.set(language,defaults:defaults)
            try check(AppLanguage.runnerEnvironment(defaults)["HUSK_APP_LANGUAGE"] == language && defaults.stringArray(forKey:"AppleLanguages") == [language], "selected language reaches new Runner environment")
        }
        AppLanguage.set("system",defaults:defaults)
        try check(AppLanguage.runnerEnvironment(defaults).isEmpty && defaults.persistentDomain(forName:suite)?["AppleLanguages"] == nil, "system language clears only the app override")
        AppLanguage.set("en;invalid",defaults:defaults)
        try check(AppLanguage.selected(defaults) == "system", "unsupported language is rejected")
        print("Account tests used only intercepted HTTP and disposable credentials/preferences; no real login or upload.")
    }
}
