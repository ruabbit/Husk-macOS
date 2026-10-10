// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

private final class LoginHTTP: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url == PlayAPI.authURL }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 1024)
            while true { let count = stream.read(&bytes, maxLength: bytes.count); if count <= 0 { break }; body.append(contentsOf: bytes.prefix(count)) }
        }
        let text = String(decoding: body, as: UTF8.self)
        let response: String
        if text.contains("Email=") { response = "Error=UnexpectedEmailPrompt" }
        else if text.contains("Token=missing-email") { response = "Token=synthetic-account-token\n" }
        else if text.contains("Token=denied") { response = "Error=BadAuthentication\n" }
        else { response = "Email=selected@example.invalid\nToken=synthetic-account-token\n" }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// Script browser navigation and cookie replies through the real transport.
/// No Chrome process, network requests or personal account data are involved.
@MainActor private func loginPolls(_ replies: [[String: Any]],
                                  _ check: (inout GoogleLoginPoller, PlayLoginPipe) async throws -> Void) async throws {
    let outgoing = Pipe(), incoming = Pipe()
    let transport = PlayLoginPipe(reader: incoming.fileHandleForReading, writer: outgoing.fileHandleForWriting)
    defer {
        transport.close(); outgoing.fileHandleForReading.readabilityHandler = nil
        try? outgoing.fileHandleForReading.close(); try? incoming.fileHandleForWriting.close()
    }
    outgoing.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        for part in data.split(separator: 0) {
            guard let request = (try? JSONSerialization.jsonObject(with: Data(part))) as? [String: Any],
                  let id = request["id"] as? Int else { continue }
            var response: [String: Any] = ["id": id]
            if (1...replies.count).contains(id), replies[id - 1]["method"] as? String == request["method"] as? String {
                response.merge(replies[id - 1].filter { $0.key != "method" }) { _, value in value }
            } else { response["error"] = ["message": "unexpected test request"] }
            if var packet = try? JSONSerialization.data(withJSONObject: response) {
                packet.append(0); try? incoming.fileHandleForWriting.write(contentsOf: packet)
            }
        }
    }
    var poller = GoogleLoginPoller()
    try await check(&poller, transport)
}

@MainActor func checkPlayLogin() async throws {
    func check(_ condition: Bool, _ label: String) throws { if !condition { throw PlayError("FAIL \(label)") }; print("PASS \(label)") }
    typealias Cookie = GoogleLoginPolicy.Cookie
    let good = Cookie(name: "oauth_token", value: "synthetic-login-token", domain: ".google.com", secure: true)
    try check(GoogleLoginPolicy.token(in: [good]) == good.value, "Google login cookie accepted")
    for cookie in [
        Cookie(name: "oauth_token", value: good.value, domain: "google.com.example.invalid", secure: true),
        Cookie(name: "oauth_token", value: good.value, domain: "accounts.google.com", secure: false),
        Cookie(name: "SID", value: good.value, domain: ".google.com", secure: true)
    ] { try check(GoogleLoginPolicy.token(in: [cookie]) == nil, "untrusted or unrelated cookie rejected") }
    try check(GoogleLoginPolicy.token(in: [good, Cookie(name: "oauth_token", value: "other-account", domain: "accounts.google.com", secure: true)]) == nil,
              "ambiguous account cookies cannot select an arbitrary account")
    try check(!GoogleLoginPolicy.allows(URL(string: "https://google.com.example.invalid")!) && !GoogleLoginPolicy.allows(URL(string: "http://accounts.google.com")!), "login navigation validates origin")
    let rejectionURL = "https://accounts.google.com/v3/signin/rejected?continue=synthetic-private-value"
    try check(GoogleLoginPolicy.isRejection(URL(string: rejectionURL)!), "Google browser rejection is recognized")
    for url in ["https://accounts.google.com.example.invalid/v3/signin/rejected",
                "https://accounts.google.com:8443/v3/signin/rejected",
                "https://accounts.google.com/EmbeddedSetup?continue=/v3/signin/rejected"] {
        try check(!GoogleLoginPolicy.isRejection(URL(string: url)!), "untrusted origins and query text cannot invent a rejection")
    }
    func targets(_ url: String, id: String = "login-page") -> [String: Any] {
        ["method": "Target.getTargets", "result": ["targetInfos": [["type": "page", "targetId": id, "url": url]]]]
    }
    let attached: [String: Any] = ["method": "Target.attachToTarget", "result": ["sessionId": "synthetic-session"]]
    let waiting: [String: Any] = ["method": "Network.getCookies", "result": ["cookies": []]]
    let accepted: [String: Any] = ["method": "Network.getCookies", "result": ["cookies": [
        ["name": good.name, "value": good.value, "domain": good.domain, "secure": true]
    ]]]
    let normal = targets(GoogleLoginPolicy.url.absoluteString), rejected = targets(rejectionURL)
    try await loginPolls([normal, attached, waiting, rejected]) { poller, transport in
        let pending = try await poller.poll(transport)
        try check(pending == nil, "unfinished Google sign-in remains pending")
        var refused = false
        do { _ = try await poller.poll(transport) }
        catch GoogleLoginFailure.browserRejected { refused = true }
        try check(refused, "navigation to rejection ends login before cookie polling or timeout")
    }
    try await loginPolls([normal, attached,
                         ["method": "Network.getCookies", "error": ["message": "renderer changed"]], rejected]) { poller, transport in
        var refused = false
        do { _ = try await poller.poll(transport) }
        catch GoogleLoginFailure.browserRejected { refused = true }
        try check(refused, "Google rejection during renderer replacement is not reported as a connection error")
    }
    try await loginPolls([rejected]) { poller, transport in
        var refused = false
        do { _ = try await poller.poll(transport) }
        catch GoogleLoginFailure.browserRejected { refused = true }
        try check(refused && !GoogleLoginFailure.browserRejected.localizedDescription.contains("synthetic-private-value"),
                  "initial rejection fails immediately without exposing URL parameters")
    }
    try await loginPolls([normal, attached, waiting,
                         targets(GoogleLoginPolicy.url.absoluteString, id: "replacement-page"), attached, accepted]) { poller, transport in
        _ = try await poller.poll(transport)
        let token = try await poller.poll(transport)
        try check(token == good.value, "login follows a replacement page and accepts its scoped cookie")
    }

    let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [LoginHTTP.self]
    let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
    let account = try await PlayAPI.accountCredentials(oauthToken: "synthetic-login-token", using: session)
    try check(account.email == "selected@example.invalid" && account.token == "synthetic-account-token", "account identity comes from Google without a second email input")
    for token in ["missing-email", "denied"] {
        var rejected = false
        do { _ = try await PlayAPI.accountCredentials(oauthToken: token, using: session) } catch { rejected = true }
        try check(rejected, "missing or refused account never falls back to an invented email")
    }

    // Exercise real pipe framing and lifecycle with synthetic replies. This
    // never launches a browser, requests a credential or opens a login window.
    let outgoing = Pipe(), incoming = Pipe()
    let transport = PlayLoginPipe(reader: incoming.fileHandleForReading, writer: outgoing.fileHandleForWriting)
    defer {
        transport.close(); outgoing.fileHandleForReading.readabilityHandler = nil
        try? outgoing.fileHandleForReading.close(); try? incoming.fileHandleForWriting.close()
    }
    outgoing.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        for part in data.split(separator: 0) {
            guard let request = (try? JSONSerialization.jsonObject(with: Data(part))) as? [String: Any],
                  let id = request["id"] as? Int, let method = request["method"] as? String else { continue }
            if method == "timeout" || method == "cancel" { continue }
            var response: [String: Any] = ["id": id]
            if method == "failure" { response["error"] = ["message": "synthetic-private-payload"] }
            else { response["result"] = ["ok": true] }
            if var packet = try? JSONSerialization.data(withJSONObject: response) {
                packet.append(0)
                try? incoming.fileHandleForWriting.write(contentsOf: packet.prefix(2))
                try? incoming.fileHandleForWriting.write(contentsOf: packet.dropFirst(2))
            }
        }
    }
    let reply = try await transport.request("success")
    try check(reply["ok"] as? Bool == true, "login pipe handles fragmented replies")
    var failure: Error?
    do { _ = try await transport.request("failure") } catch { failure = error }
    try check(failure != nil && failure?.localizedDescription.contains("synthetic-private-payload") == false, "protocol errors do not expose payloads")
    var timedOut = false
    do { _ = try await transport.request("timeout", timeout: 0.03) } catch { timedOut = true }
    try check(timedOut, "unresponsive login pipe times out")
    let pending = Task { try await transport.request("cancel") }
    await Task.yield(); pending.cancel()
    var cancelled = false
    do { _ = try await pending.value } catch is CancellationError { cancelled = true }
    try check(cancelled, "cancelled login request releases its continuation")
    let disconnected = Task { try await transport.request("cancel") }
    await Task.yield(); transport.close()
    var closed = false
    do { _ = try await disconnected.value } catch { closed = true }
    try check(closed, "closed login pipe releases outstanding requests")
}
