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
