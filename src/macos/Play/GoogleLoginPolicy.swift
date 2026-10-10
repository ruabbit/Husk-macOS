// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

enum GoogleLoginFailure: LocalizedError {
    case browserRejected

    var errorDescription: String? {
        "Google 拒绝了这个登录窗口，提示“此浏览器或应用可能不安全”。本次登录未完成，Husk 尚未取得 Play 会话。"
    }
}

enum GoogleLoginPolicy {
    static let url = URL(string: "https://accounts.google.com/EmbeddedSetup")!
    struct Cookie: Decodable {
        let name: String
        let value: String
        let domain: String
        let secure: Bool
    }
    static func token(in cookies: [Cookie]) -> String? {
        let tokens = Set(cookies.filter {
            $0.name == "oauth_token" && $0.secure && !$0.value.isEmpty && $0.value.count <= 16_384 &&
            ["accounts.google.com", ".accounts.google.com", ".google.com", "google.com"].contains($0.domain) &&
            !$0.value.contains(where: \.isWhitespace)
        }.map(\.value))
        return tokens.count == 1 ? tokens.first : nil
    }
    static func allows(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil &&
        (url.host == "google.com" || url.host?.hasSuffix(".google.com") == true)
    }
    static func isRejection(_ url: URL) -> Bool {
        guard allows(url), url.host == "accounts.google.com", url.port == nil || url.port == 443 else { return false }
        return ["/signin/rejected", "/v2/signin/rejected", "/v3/signin/rejected"].contains(url.path)
    }
}
