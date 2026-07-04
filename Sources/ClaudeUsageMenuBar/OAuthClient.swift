import Foundation

enum OAuthError: Error {
    case notImported
    case tokenExchangeFailed(String)
    case noRefreshToken
    /// The refresh token was rejected (e.g. rotated/invalidated by Claude Code
    /// itself refreshing its own copy first) — needs a fresh reconnect, not a retry.
    case refreshTokenInvalid
}

private struct OAuthErrorBody: Decodable {
    let error: String
}

struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Double?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

enum OAuthClient {
    /// One-time import of Claude Code CLI's already-granted OAuth credential from the
    /// Keychain. From then on this app refreshes and uses its own copy independently.
    static func importFromClaudeCode() throws {
        guard let credential = KeychainStore.loadClaudeCodeCredential() else {
            throw OAuthError.notImported
        }
        let tokens = StoredTokens(
            accessToken: credential.claudeAiOauth.accessToken,
            refreshToken: credential.claudeAiOauth.refreshToken,
            expiresAt: Date(timeIntervalSince1970: credential.claudeAiOauth.expiresAt / 1000)
        )
        KeychainStore.save(tokens)
    }

    /// Returns a valid access token, refreshing via the stored refresh token if needed.
    static func validAccessToken() async throws -> String {
        guard let stored = KeychainStore.load() else { throw OAuthError.noRefreshToken }
        if stored.expiresAt.timeIntervalSinceNow > 60 {
            return stored.accessToken
        }
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": stored.refreshToken,
            "client_id": OAuthConfig.clientId
        ]
        let tokenResponse = try await postToken(body: body)
        try save(tokenResponse, fallbackRefreshToken: stored.refreshToken)
        return tokenResponse.accessToken
    }

    static func logout() {
        KeychainStore.clear()
    }

    static var isLoggedIn: Bool {
        KeychainStore.load() != nil
    }

    private static func save(_ response: TokenResponse, fallbackRefreshToken: String? = nil) throws {
        guard let refreshToken = response.refreshToken ?? fallbackRefreshToken else {
            throw OAuthError.tokenExchangeFailed("no refresh_token in response")
        }
        let expiresAt = Date().addingTimeInterval(response.expiresIn ?? 3600)
        KeychainStore.save(StoredTokens(accessToken: response.accessToken, refreshToken: refreshToken, expiresAt: expiresAt))
    }

    private static func postToken(body: [String: Any]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: OAuthConfig.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            if let errorBody = try? JSONDecoder().decode(OAuthErrorBody.self, from: data), errorBody.error == "invalid_grant" {
                throw OAuthError.refreshTokenInvalid
            }
            let text = String(data: data, encoding: .utf8) ?? "unknown error"
            throw OAuthError.tokenExchangeFailed(text)
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
}
