// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// Shared release selection for the iOS and macOS Geode installers.
enum GeodeRelease {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static func json(_ url: URL, session: URLSession = .shared) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Husk", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure(message: "\(url.host ?? "Server") did not return a release (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
        }
        return object
    }
    static func parse(_ object: [String: Any]) throws -> (String, URL) {
        let payload = object["payload"] as? [String: Any] ?? object
        guard let version = payload["version"] as? String, !version.isEmpty,
              version.count < 80, version.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-+".contains($0)) }),
              let downloads = payload["downloads"] as? [String: Any] else {
            throw Failure(message: "Geode has no release for this version of Geometry Dash.")
        }
        let entry = downloads["android64"]
        let link = (entry as? String) ?? ((entry as? [String: Any])?["url"] as? String)
        guard let link, let url = URL(string: link), url.scheme == "https", url.host != nil else {
            throw Failure(message: "Geode's release has no Android arm64 download.")
        }
        return (version, url)
    }
    static func latest(versionCode: Int, session: URLSession = .shared) async throws -> (String, URL) {
        let url = URL(string: "https://api.geode-sdk.org/v1/loader/versions/latest?gd=\(versionCode)&platform=android&prerelease=false")!
        return try parse(await json(url, session: session))
    }
    static func launcher(_ object: [String: Any]) throws -> URL {
        let assets = object["assets"] as? [[String: Any]] ?? []
        let links = assets.compactMap { $0["browser_download_url"] as? String }.filter { $0.hasSuffix(".apk") }
        guard let link = links.first(where: { !$0.contains("android32") && !$0.contains("armeabi") }),
              let url = URL(string: link), url.scheme == "https", url.host != nil else {
            throw Failure(message: "Geode's launcher release has no 64-bit APK.")
        }
        return url
    }
    static func launcherURL(session: URLSession = .shared) async throws -> URL {
        try launcher(await json(URL(string: "https://api.github.com/repos/geode-sdk/android-launcher/releases/latest")!, session: session))
    }
}
