import Foundation

enum OAuthConfig {
    // Same OAuth client Claude Code's CLI uses; needed to refresh the imported token.
    static let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let tokenURL = "https://platform.claude.com/v1/oauth/token"
    static let usageURL = "https://api.anthropic.com/api/oauth/usage"
    static let keychainService = "com.github.claude-usage-menubar"
    static let keychainAccount = "oauth-tokens"
}
