// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Security

protocol PlaySessionStorage {
    func load() throws -> PlaySession?
    func save(_ session: PlaySession) throws
    func remove() throws
}

struct PlayCredentials: PlaySessionStorage {
    private let service = "org.husk.HuskMac.play"
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service, kSecAttrAccount as String: "session"] }
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw PlayError("无法访问 Play 登录凭据的钥匙串（\(status)）。") }
    }
    func load() throws -> PlaySession? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data else { throw PlayError("Play 会话数据无效，请退出后重新登录。") }
        return try JSONDecoder().decode(PlaySession.self, from: data)
    }
    func save(_ session: PlaySession) throws {
        let data = try JSONEncoder().encode(session)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            try check(SecItemAdd(q as CFDictionary, nil))
        } else { try check(status) }
    }
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
}
