import Foundation
import OpenClawKit

// OA (corporate OAuth) storage. Mirrors Windows SettingsData.cs + SettingsManager.cs.
//  - secrets (access/refresh token, Dify key) → Keychain (replaces Windows DPAPI)
//  - non-secret profile (OaUserInfo, expiry, hub URL) → UserDefaults plaintext
//    (Windows also stores OaUserInfo in plaintext settings.json)

/// OA user profile snapshot (from OAuthUserInfo.ashx). Plaintext-persisted.
/// `departmentId` is a string (mirrors Windows OaUserInfo — NOT an int).
struct OaUserInfo: Codable, Hashable {
    var userId: String?
    var username: String?
    var displayName: String?
    var email: String?
    var departmentId: String?   // string, not int
    var departmentName: String?
    var position: String?
    var roles: [String]?
}

/// Keychain-backed secrets. Wraps `GenericPasswordKeychainStore`.
/// Keys: `ai.openclaw.oa` / `access-token`, `ai.openclaw.oa` / `refresh-token`,
///       `ai.openclaw.skills` / `dify-api-key`.
enum OAKeychain {
    private static let oaService = "ai.openclaw.oa"
    private static let skillsService = "ai.openclaw.skills"
    private static let accessTokenAccount = "access-token"
    private static let refreshTokenAccount = "refresh-token"
    private static let difyApiKeyAccount = "dify-api-key"

    static var accessToken: String? {
        GenericPasswordKeychainStore.loadString(service: self.oaService, account: self.accessTokenAccount)
    }

    static func saveAccessToken(_ value: String) {
        GenericPasswordKeychainStore.saveString(value, service: self.oaService, account: self.accessTokenAccount)
    }

    static var refreshToken: String? {
        GenericPasswordKeychainStore.loadString(service: self.oaService, account: self.refreshTokenAccount)
    }

    static func saveRefreshToken(_ value: String) {
        GenericPasswordKeychainStore.saveString(value, service: self.oaService, account: self.refreshTokenAccount)
    }

    static var difyApiKey: String? {
        GenericPasswordKeychainStore.loadString(service: self.skillsService, account: self.difyApiKeyAccount)
    }

    static func saveDifyApiKey(_ value: String) {
        GenericPasswordKeychainStore.saveString(value, service: self.skillsService, account: self.difyApiKeyAccount)
    }

    /// Clear OA session secrets (access + refresh). Leaves the Dify key intact.
    static func clearOaSession() {
        GenericPasswordKeychainStore.delete(service: self.oaService, account: self.accessTokenAccount)
        GenericPasswordKeychainStore.delete(service: self.oaService, account: self.refreshTokenAccount)
    }
}

/// Plaintext persistence for non-secret OA session data.
/// (Endpoint URLs live in EnvConfig, not here — not user-editable.)
enum OASettings {
    private static let userInfoKey = "openclaw.oa.userInfo"
    private static let expiresAtKey = "openclaw.oa.expiresAtMs"

    static var userInfo: OaUserInfo? {
        guard let data = UserDefaults.standard.data(forKey: self.userInfoKey) else { return nil }
        return try? JSONDecoder().decode(OaUserInfo.self, from: data)
    }

    static func saveUserInfo(_ value: OaUserInfo?) {
        if let value, let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: self.userInfoKey)
        } else {
            UserDefaults.standard.removeObject(forKey: self.userInfoKey)
        }
    }

    /// Absolute token expiry (Unix epoch ms). 0 = no token.
    static var expiresAtMs: Int64 {
        Int64(UserDefaults.standard.double(forKey: self.expiresAtKey))
    }

    static func saveExpiresAtMs(_ value: Int64) {
        UserDefaults.standard.set(Double(value), forKey: self.expiresAtKey)
    }

    /// Clear OA profile + expiry (Keychain secrets cleared separately via OAKeychain).
    static func clear() {
        UserDefaults.standard.removeObject(forKey: self.userInfoKey)
        UserDefaults.standard.removeObject(forKey: self.expiresAtKey)
    }
}
