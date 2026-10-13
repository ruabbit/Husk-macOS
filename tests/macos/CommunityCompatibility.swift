// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import AppKit

private final class CompatibilityProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, data) = try Self.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@main struct CompatibilityTests {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("husk-compat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let defaultsName = "husk.compat.test.\(UUID().uuidString)", defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CompatibilityProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let sites = [URL(string: "https://first.invalid")!, URL(string: "https://second.invalid")!]
        let cache = root.appendingPathComponent("cache/list.json")
        if CommandLine.arguments.contains("--live-read") {
            let live = CompatibilityStore(cache: cache, defaults: defaults)
            await live.refresh(force: true)
            guard live.error == nil, !live.entries.isEmpty else { throw URLError(.badServerResponse) }
            print("PASS public GET and typed decode: \(live.entries.count) entries; site \(live.workingSite?.host ?? "?"); no report sent")
            return
        }
        let store = CompatibilityStore(session: session, sites: sites, cache: cache, defaults: defaults)
        func check(_ ok: Bool, _ message: String) throws {
            guard ok else { throw NSError(domain: message, code: 1) }; print("PASS \(message)")
        }
        let list = Data(#"{"apps":[{"package":"org.husk.fixture","name":"Fixture","official":{"status":"opens","note":"iPhone test"},"community":{"reports":2,"counts":{"works":2}}}]}"#.utf8)
        var requests: [URLRequest] = []
        CompatibilityProtocol.handler = { request in
            requests.append(request)
            if request.url?.host == "first.invalid" { return (503, Data()) }
            return (200, list)
        }
        await store.refresh()
        try check(requests.count == 2 && store.workingSite == sites[1], "GET falls back after server failure")
        try check(store.entry("org.husk.fixture")?.status == .opens, "official result retains its source")
        await store.refresh()
        try check(requests.count == 2, "fresh cache avoids duplicate GET")
        let restored = CompatibilityStore(session: session, sites: sites, cache: cache, defaults: defaults)
        try check(restored.entry("org.husk.fixture")?.community.reports == 2, "offline cache restored")
        requests = []
        CompatibilityProtocol.handler = { request in requests.append(request); return (403, Data()) }
        await store.refresh(force: true)
        try check(requests.count == 1 && store.error != nil && store.entry("org.husk.fixture") != nil, "4xx preserves cache without fallback")
        CompatibilityProtocol.handler = { _ in (200, Data("invalid JSON".utf8)) }
        await store.refresh(force: true)
        try check(store.error != nil && store.entry("org.husk.fixture") != nil, "malformed response preserves cache")
        try check(!store.shouldAsk("org.husk.fixture"), "macOS post-session prompts default off")
        defaults.set(true, forKey: CompatibilityStore.askKey)
        try check(store.shouldAsk("org.husk.fixture"), "opt-in enables prompt")
        store.markAsked("org.husk.fixture")
        try check(!store.shouldAsk("org.husk.fixture"), "prompt once per package and build")

        let icon = root.appendingPathComponent("icon.png")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: icon)
        var payload: [String: String] = [:], posts = 0
        CompatibilityProtocol.handler = { request in
            if request.httpMethod == "POST" {
                posts += 1
                var data = request.httpBody ?? Data()
                if let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var bytes = [UInt8](repeating: 0, count: 4096)
                    while true { let n = stream.read(&bytes, maxLength: bytes.count); if n <= 0 { break }; data.append(contentsOf: bytes.prefix(n)) }
                }
                payload = try JSONDecoder().decode([String: String].self, from: data)
                return (201, Data("{}".utf8))
            }
            return (200, list)
        }
        try await store.send(package: "org.husk.fixture", name: "Fixture", isGame: true, status: .works,
            notes: "local fixture", author: "", iconPath: icon.path, runtime: "java")
        try check(posts == 1 && payload["ios"]?.hasPrefix("macOS ") == true && payload["device"]?.hasPrefix("Mac") == true &&
                  payload["notes"]?.contains("runtime: java") == true && payload["author"] == nil, "report identifies macOS and excludes blank author")
        let png = payload["icon"].flatMap { Data(base64Encoded: $0) }.flatMap { NSBitmapImageRep(data: $0) }
        try check(png?.pixelsWide == 128 && png?.pixelsHigh == 128, "first report icon is a bounded PNG")
        posts = 0
        CompatibilityProtocol.handler = { _ in posts += 1; throw URLError(.networkConnectionLost) }
        do {
            try await store.send(package: "org.husk.fixture", name: "Fixture", isGame: true, status: .opens, notes: "", author: "")
            throw NSError(domain: "expected network failure", code: 1)
        } catch let error as URLError { try check(error.code == .networkConnectionLost && posts == 1, "ambiguous POST is never retried at another site") }
        print("PASS compatibility: isolated protocol only; no public report sent")
    }
}
