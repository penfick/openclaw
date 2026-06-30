import AppKit
import Foundation

// OA (corporate) OAuth. Mirrors Windows OAuthAuthService.cs.
// Flow: startLogin() opens browser → corporate OA redirects tclaw://oauth/callback →
// MenuBar.application(_:open:) routes to handle(callback:) → exchange code → fetch UserInfo →
// persist (Keychain tokens + UserDefaults profile) → schedule refresh.
// State is @Observable so settings UI re-renders on login/logout.

enum OAConfig {
    // Sourced from EnvConfig (test vs prod, set in code — not user-editable).
    static var oaBaseUrl: String { EnvConfig.oaBaseUrl }
    static let clientId = "xknn9sEiUnyRjH3u1mTYh6inWoxu5yQb"
    static let clientSecret = "dAkkMKWpdeM1QTS-CMqW6Sr9xxRpLQ6YjHKHFS_tLoQCIVkA"
    static let scope = "basic profile department role"
    static let redirectUri = "tclaw://oauth/callback"
    static let refreshLeadTimeMs: Int64 = 5 * 60 * 1000   // refresh 5 min before expiry
    static let minRefreshDelayMs: Int64 = 60 * 1000        // never sooner than 60s
}

@MainActor
@Observable
final class OAAuthCoordinator {
    static let shared = OAAuthCoordinator()

    private(set) var authenticated = false
    private(set) var userInfo: OaUserInfo?
    private(set) var expiresAtMs: Int64 = 0
    var lastError: String?

    private var pendingLoginState: String?
    private var refreshTask: Task<Void, Never>?
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - State

    private func pushState(authenticated: Bool, userInfo: OaUserInfo? = nil, expiresAtMs: Int64 = 0) {
        self.authenticated = authenticated
        if let userInfo { self.userInfo = userInfo }
        if expiresAtMs > 0 { self.expiresAtMs = expiresAtMs }
        if !authenticated {
            self.userInfo = nil
            self.expiresAtMs = 0
        }
    }

    // MARK: - Restore (call once at app start)

    func restoreSession() async {
        guard let token = OAKeychain.accessToken, !token.isEmpty else {
            self.pushState(authenticated: false)
            return
        }
        let expiresAt = OASettings.expiresAtMs
        let info = OASettings.userInfo
        let now = Self.currentMs()
        if expiresAt > 0 && now >= expiresAt {
            // persisted token already expired — try refresh; else logout
            if let refresh = OAKeychain.refreshToken, !refresh.isEmpty {
                self.pushState(authenticated: true, userInfo: info, expiresAtMs: expiresAt)
                _ = await self.refreshAccessToken()
            } else {
                await self.logout()
            }
            return
        }
        self.pushState(authenticated: true, userInfo: info, expiresAtMs: expiresAt)
        self.scheduleRefresh(expiresAtMs: expiresAt)
    }

    // MARK: - Login

    /// Opens the browser to the authorize URL. Returns whether the browser launched.
    /// Completion is async (via the tclaw:// callback), not awaited here.
    @discardableResult
    func startLogin() -> Bool {
        let state = Self.randomState()
        self.pendingLoginState = state
        guard let url = URL(string: Self.buildAuthorizeUrl(state: state)) else {
            self.lastError = "授权 URL 无效。"
            return false
        }
        return NSWorkspace.shared.open(url)
    }

    /// Handle the tclaw://oauth/callback?code=&state= URL.
    func handle(callback url: URL) async -> Bool {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = comps?.queryItems ?? []
        let code = items.first(where: { $0.name == "code" })?.value
        let state = items.first(where: { $0.name == "state" })?.value
        let error = items.first(where: { $0.name == "error" })?.value

        if let error, !error.isEmpty {
            self.lastError = "登录失败：\(error)"
            self.pushState(authenticated: false)
            return false
        }
        guard let code, !code.isEmpty else {
            self.lastError = "回调缺少 code。"
            self.pushState(authenticated: false)
            return false
        }
        // state is a SOFT check (mismatch only warns, never rejects) — mirrors Windows.
        if let pending = self.pendingLoginState, !pending.isEmpty,
           let state, state != pending
        {
            self.lastError = nil // soft mismatch: warn-only, continue
        }
        self.pendingLoginState = nil
        return await self.completeLogin(code: code)
    }

    private func completeLogin(code: String) async -> Bool {
        do {
            guard let tokenResp = try await self.exchangeCode(code: code) else {
                self.lastError = "Token 交换失败。"
                self.pushState(authenticated: false)
                return false
            }
            let info = (try? await self.fetchUserInfo(accessToken: tokenResp.accessToken)) ?? OASettings.userInfo
            let expiresAt = Self.currentMs() + Int64(tokenResp.expiresIn > 0 ? tokenResp.expiresIn : 3600) * 1000
            self.persist(accessToken: tokenResp.accessToken, refreshToken: tokenResp.refreshToken, expiresAtMs: expiresAt, userInfo: info)
            self.pushState(authenticated: true, userInfo: info, expiresAtMs: expiresAt)
            self.scheduleRefresh(expiresAtMs: expiresAt)
            return true
        } catch {
            self.lastError = "登录失败：\(error.localizedDescription)"
            self.pushState(authenticated: false)
            return false
        }
    }

    // MARK: - Refresh

    func refreshAccessToken() async -> Bool {
        guard let refresh = OAKeychain.refreshToken, !refresh.isEmpty else {
            await self.logout()
            return false
        }
        do {
            guard let tokenResp = try await self.exchangeRefresh(refreshToken: refresh) else {
                await self.logout()
                return false
            }
            let expiresAt = Self.currentMs() + Int64(tokenResp.expiresIn > 0 ? tokenResp.expiresIn : 3600) * 1000
            let info = OASettings.userInfo
            self.persist(accessToken: tokenResp.accessToken, refreshToken: tokenResp.refreshToken ?? refresh, expiresAtMs: expiresAt, userInfo: info)
            self.pushState(authenticated: true, userInfo: info, expiresAtMs: expiresAt)
            self.scheduleRefresh(expiresAtMs: expiresAt)
            return true
        } catch {
            await self.logout()
            return false
        }
    }

    private func scheduleRefresh(expiresAtMs: Int64) {
        self.refreshTask?.cancel()
        let now = Self.currentMs()
        var delayMs = expiresAtMs - now - OAConfig.refreshLeadTimeMs
        if delayMs < OAConfig.minRefreshDelayMs { delayMs = OAConfig.minRefreshDelayMs }
        let nanos = UInt64(max(0, delayMs)) * 1_000_000
        self.refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, let self else { return }
            _ = await self.refreshAccessToken()
        }
    }

    /// Valid access token for REST clients; refreshes synchronously if expired.
    func validAccessToken() async -> String? {
        let now = Self.currentMs()
        if self.expiresAtMs > 0 && now >= self.expiresAtMs {
            let ok = await self.refreshAccessToken()
            if !ok { return nil }
        }
        return OAKeychain.accessToken
    }

    // MARK: - Logout

    func logout() async {
        if let token = OAKeychain.accessToken, !token.isEmpty {
            _ = try? await self.revoke(token: token)   // best-effort
        }
        self.refreshTask?.cancel()
        self.refreshTask = nil
        OAKeychain.clearOaSession()
        OASettings.clear()
        self.pushState(authenticated: false)
    }

    // MARK: - HTTP

    private struct TokenResponse {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int
    }

    private func exchangeCode(code: String) async throws -> TokenResponse? {
        let body = "grant_type=authorization_code"
            + "&code=\(Self.encode(code))"
            + "&client_id=\(Self.encode(OAConfig.clientId))"
            + "&client_secret=\(Self.encode(OAConfig.clientSecret))"
            + "&redirect_uri=\(Self.encode(OAConfig.redirectUri))"
        return try await self.postToken(body: body)
    }

    private func exchangeRefresh(refreshToken: String) async throws -> TokenResponse? {
        let body = "grant_type=refresh_token"
            + "&refresh_token=\(Self.encode(refreshToken))"
            + "&client_id=\(Self.encode(OAConfig.clientId))"
            + "&client_secret=\(Self.encode(OAConfig.clientSecret))"
        return try await self.postToken(body: body)
    }

    private func postToken(body: String) async throws -> TokenResponse? {
        guard let url = URL(string: "\(OAConfig.oaBaseUrl)/OAuthToken.ashx") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.data(using: .utf8)
        let (data, resp) = try await self.session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "OA", code: 0, userInfo: [NSLocalizedDescriptionKey: "token endpoint failed"])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let accessToken = json["access_token"] as? String ?? ""
        guard !accessToken.isEmpty else { return nil }
        return TokenResponse(
            accessToken: accessToken,
            refreshToken: json["refresh_token"] as? String,
            expiresIn: Self.parseInt(json["expires_in"]))
    }

    private func fetchUserInfo(accessToken: String) async throws -> OaUserInfo {
        guard let url = URL(string: "\(OAConfig.oaBaseUrl)/OAuthUserInfo.ashx") else {
            throw NSError(domain: "OA", code: 0, userInfo: [NSLocalizedDescriptionKey: "userinfo url invalid"])
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await self.session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "OA", code: 0, userInfo: [NSLocalizedDescriptionKey: "userinfo failed"])
        }
        return Self.parseUserInfo(data: data)
    }

    private func revoke(token: String) async throws {
        guard let url = URL(string: "\(OAConfig.oaBaseUrl)/Revoke.ashx") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "token=\(Self.encode(token))".data(using: .utf8)
        _ = try await self.session.data(for: req)
    }

    // MARK: - Persist

    private func persist(accessToken: String, refreshToken: String?, expiresAtMs: Int64, userInfo: OaUserInfo?) {
        OAKeychain.saveAccessToken(accessToken)
        if let refreshToken { OAKeychain.saveRefreshToken(refreshToken) }
        OASettings.saveExpiresAtMs(expiresAtMs)
        OASettings.saveUserInfo(userInfo)
    }

    // MARK: - Helpers

    /// scope MUST use '+' not '%20' — corporate OA rejects %20 and login silently no-ops.
    private static func buildAuthorizeUrl(state: String) -> String {
        let scope = OAConfig.scope.replacingOccurrences(of: " ", with: "+")
        return "\(OAConfig.oaBaseUrl)/AuthorizationGrant.aspx?response_type=code"
            + "&client_id=\(encode(OAConfig.clientId))"
            + "&redirect_uri=\(encode(OAConfig.redirectUri))"
            + "&scope=\(scope)"
            + "&state=\(encode(state))"
    }

    // Uri.EscapeDataString equivalent: percent-encode everything except RFC 3986 unreserved
    // (A-Za-z0-9-._~). .urlQueryAllowed leaves ":" "/" un-encoded, which the OA server rejects
    // for redirect_uri (it must arrive as tclaw%3A%2F... so OA's ReturnUrl re-encode yields %25).
    private static let unreserved: CharacterSet = .alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    private static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? s
    }

    private static func randomState() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private static func currentMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private static func parseInt(_ any: Any?) -> Int {
        if let n = any as? Int { return n }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String, let n = Int(s) { return n }
        return 0
    }

    private static func parseUserInfo(data: Data) -> OaUserInfo {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return OaUserInfo()
        }
        func str(_ keys: String...) -> String? {
            for key in keys {
                if let value = json[key] as? String, !value.isEmpty { return value }
            }
            return nil
        }
        var roles: [String]?
        if let arr = json["roles"] as? [Any] {
            let parsed = arr.compactMap { $0 as? String }
            roles = parsed.isEmpty ? nil : parsed
        }
        return OaUserInfo(
            userId: str("user_id", "userid"),
            username: str("username"),
            displayName: str("display_name", "displayName", "name"),
            email: str("email", "mail"),
            departmentId: str("department_id"),
            departmentName: str("department_name"),
            position: str("position"),
            roles: roles)
    }
}
