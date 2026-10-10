// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

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
}
