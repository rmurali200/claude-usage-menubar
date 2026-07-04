import Foundation
import Security

struct StoredTokens: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

enum KeychainStore {
    static func save(_ tokens: StoredTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: OAuthConfig.keychainService,
            kSecAttrAccount as String: OAuthConfig.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func load() -> StoredTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: OAuthConfig.keychainService,
            kSecAttrAccount as String: OAuthConfig.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(StoredTokens.self, from: data)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: OAuthConfig.keychainService,
            kSecAttrAccount as String: OAuthConfig.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Reads Claude Code CLI's own stored OAuth credential (read-only; Claude Code manages
    /// this entry itself, we never write to it).
    static func loadClaudeCodeCredential() -> ClaudeCodeCredential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(ClaudeCodeCredential.self, from: data)
    }
}

struct ClaudeCodeCredential: Decodable {
    struct OAuth: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Double // epoch milliseconds
    }
    let claudeAiOauth: OAuth
}
