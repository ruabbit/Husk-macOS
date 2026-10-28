// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import AppKit
import SwiftUI

private func document(_ package: String, downloads: String = "1,000,000,000+", compact: String = "1B+") -> Data {
    var d = ProtoWriter()
    d.string(1, package); d.string(5, "Fixture & friends"); d.string(6, "Fixture developer")
    d.string(7, "<b>Explore</b> &amp; build<br><ol><li>First</li><li>Second</li></ol>")
    d.string(27, "An offline protocol fixture")
    for (kind, url, width, height) in [
        (4, "icon", 512, 512), (2, "banner", 1024, 500), (1, "portrait", 1080, 1920),
        (1, "landscape", 1920, 1080), (1, "unknown", 0, 0), (3, "trailer", 0, 0), (13, "poster", 1280, 720)
    ] {
        d.message(10) { image in
            image.int(1, kind); image.string(5, "https://media.invalid/" + url)
            image.message(2) { $0.int(3, width); $0.int(4, height) }
        }
    }
    d.message(8) { $0.int(1, 0); $0.string(7, "Free") }
    d.message(13) { details in
        details.message(1) { app in
            app.int(3, package.hasSuffix("direct") ? 44 : 0); app.string(4, "4.4")
            app.int(9, 1_234_567); app.string(13, downloads); app.string(61, compact)
            app.string(16, "Oct 28, 2026"); app.message(64) { $0.string(1, "Jan 1, 2020") }
            app.string(15, "<i>New</i> &amp; improved"); app.string(30, "Contains ads")
            app.string(67, "$0.99 per item"); app.string(18, "GAME")
            app.message(66) { groups in
                groups.message(2) { group in group.message(1) { $0.string(1, "Offline") } }
                groups.message(1) { group in
                    group.message(1) { $0.string(1, "Puzzle") }; group.message(1) { $0.string(1, "Offline") }
                }
            }
            app.message(41) { $0.string(1, "Build worlds"); $0.string(1, "Play together"); $0.string(4, "Editors' Choice") }
            app.string(11, "support@example.invalid"); app.string(12, "https://example.invalid")
        }
    }
    d.message(14) { $0.string(1, "4.8"); $0.string(18, "37M") }
    d.message(50) { $0.string(1, "Everyone") }; d.message(15) { $0.string(18, "https://example.invalid/privacy") }
    return d.data
}

private final class DetailsHTTP: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true } // all requests stay in this fixture
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let package = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "doc" }?.value ?? ""
        let valid = request.url?.absoluteString.hasPrefix(PlayAPI.fdfe + "details?") == true
            && request.httpMethod == "GET" && request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-only"
        let status = !valid ? 400 : package.hasSuffix("expired") ? 401 : package.hasSuffix("denied") ? 503 : 200
        var payload = ProtoWriter()
        payload.message(2) { details in
            details.bytes(4, document(package))
            details.message(6) { cluster in cluster.message(2) { info in info.message(11) { $0.int(2, 77) } } }
        }
        var wrapper = ProtoWriter()
        if package.hasSuffix("prefetched") {
            wrapper.message(3) { outer in outer.message(2) { $0.bytes(1, payload.data) } }
        } else { wrapper.bytes(1, payload.data) }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: wrapper.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct PlayDetailsTests {
    @MainActor static func main() async {
        do { try await run() } catch { print("FAIL \(error)"); exit(1) }
    }
    @MainActor static func run() async throws {
        func check(_ condition: Bool, _ label: String) throws {
            guard condition else { throw PlayError(label) }; print("PASS \(label)")
        }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DetailsHTTP.self]
        let client = URLSession(configuration: config); defer { client.invalidateAndCancel() }
        let session = PlaySession(email: "fixture@example.invalid", bearer: "fixture-only")
        for suffix in ["direct", "fallback", "prefetched"] {
            guard let app = try await PlayAPI.details(packageName: "org.husk." + suffix, session: session, using: client) else { throw PlayError("missing details") }
            try check(app.versionCode == (suffix == "direct" ? 44 : 77), "\(suffix) details version and response wrapper")
            try check(app.title == "Fixture & friends" && app.isFree && app.isGame && app.sizeBytes == 1_234_567, "\(suffix) identity, price and game classification")
            try check(app.feature == "https://media.invalid/banner" && app.screenshotURLs.count == 3 && !app.screenshotURLs.contains(app.feature!), "\(suffix) banner stays separate from screenshots")
            try check(app.screenshotRatios == [1080.0 / 1920, 1920.0 / 1080, 0] && app.trailer?.url == "https://media.invalid/trailer" && app.trailer?.thumbnail == "https://media.invalid/poster", "\(suffix) screenshot aspect ratios and trailer metadata")
            try check(app.installs == "1B+" && app.rating == 4.8 && app.reviews == "37M" && app.contentRating == "Everyone", "\(suffix) compact counts and ratings")
            try check(app.tags == ["Puzzle", "Offline"] && app.highlights == ["Build worlds", "Play together"] && app.award == "Editors' Choice", "\(suffix) ordered unique tags, highlights and award")
            try check(app.updated == "Oct 28, 2026" && app.released == "Jan 1, 2020" && app.whatsNew.contains("<i>New</i>") && !app.ads.isEmpty && !app.purchases.isEmpty, "\(suffix) dates, release notes and commercial information survive version fallback")
            try check(app.website == "https://example.invalid" && app.privacy.hasSuffix("/privacy") && app.email == "support@example.invalid", "\(suffix) developer links")
        }
        for suffix in ["expired", "denied"] {
            var rejected = false
            do { _ = try await PlayAPI.details(packageName: "org.husk." + suffix, session: session, using: client) }
            catch let error as PlayError { rejected = error.httpStatus == (suffix == "expired" ? 401 : 503) }
            try check(rejected, "\(suffix) response cannot publish fixture details")
        }
        for (raw, expected) in [("1,500,000+", "1.5M+"), ("999+", "999+"), (String(repeating: "9", count: 400), String(repeating: "9", count: 400)), (String(Int.max), String(Int.max))] {
            let app = PlayAPI.PlayApp.from(doc: ProtoMessage(document("org.husk.count", downloads: raw, compact: "")))!
            try check(app.installs == expected, "bounded compact count fallback (\(raw.count) characters)")
        }
        let rich = PlayText.attributed("<b>Bold</b> <i>Italic</i> **Markdown** &amp; &#x4E2D;<ol><li>One</li><li>Two</li></ol><ul><li>Bullet</li></ul><a href='https://example.invalid'>Web</a> <a href='mailto:help@example.invalid'>Mail</a> <a href='file:///tmp/private'>File</a> [Unsafe](javascript:alert)")
        let plain = String(rich.characters)
        try check(plain.contains("Bold Italic Markdown & 中") && plain.contains("1. One") && plain.contains("2. Two") && plain.contains("• Bullet"), "rich text entities, HTML lists and inline Markdown")
        try check(rich.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true } && rich.runs.contains { $0.inlinePresentationIntent?.contains(.emphasized) == true }, "rich text preserves emphasis")
        try check(Set(rich.runs.compactMap { $0.link?.scheme }) == Set(["https", "mailto"]) && plain.contains("File") && plain.contains("Unsafe"), "unsafe link schemes become plain text")
        try check(PlayImages.sized("https://play-lh.googleusercontent.com/image", height: 500)?.absoluteString.hasSuffix("=h500") == true, "Google image resizing")
        for url in ["https://googleusercontent.com.evil.invalid/image", "https://cdn.invalid/googleusercontent.com", "https://play-lh.googleusercontent.com/image?token=keep", "https://play-lh.googleusercontent.com/image#fragment", "https://play-lh.googleusercontent.com/image=h100"] {
            try check(PlayImages.sized(url, height: 500)?.absoluteString == url, "preserve non-Google host or existing URL parameters")
        }
        try check(PlayImages.webURL("file:///tmp/image") == nil && PlayImages.webURL("https:invalid") == nil, "images require web origins")
        var sparse = ProtoWriter(); sparse.string(1, "org.husk.empty"); sparse.string(5, "No optional metadata")
        let empty = PlayAPI.PlayApp.from(doc: ProtoMessage(sparse.data))!
        try check(empty.feature == nil && empty.screenshotURLs.isEmpty && empty.installs.isEmpty && !empty.isGame, "missing optional fields remain empty")
        // Layout the actual Mac page without a window or remote media request.
        let host = NSHostingView(rootView: MacPlayDetails(app: empty) { Text("Install") } compatibility: { Text("Compatibility") })
        host.frame = NSRect(x: 0, y: 0, width: 430, height: 700); host.layoutSubtreeIfNeeded()
        try check(host.fittingSize.width.isFinite && host.fittingSize.height > 0, "Mac detail page lays out at narrow width with absent media")
        let gallery = MacPlayGallery(title: "Fixture", urls: [], selected: -1)
        let decoded = try JSONDecoder().decode(MacPlayGallery.self, from: JSONEncoder().encode(gallery))
        let imageHost = NSHostingView(rootView: MacPlayGalleryView(gallery: decoded))
        imageHost.frame = NSRect(x: 0, y: 0, width: 700, height: 500); imageHost.layoutSubtreeIfNeeded()
        try check(imageHost.fittingSize.height > 0, "restored empty screenshot window has an empty state")
    }
}
