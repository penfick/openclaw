import Foundation
import Security

/// Writes the minimal local-gateway defaults needed to "run + connect", without
/// running the interactive openclaw wizard (models / channels / skills).
///
/// Cross-platform defaults match docs/MAC_PORT_HANDOFF.md §7 and Windows
/// `ConfigureGatewayStep.WriteNativeGatewayConfigAsync`:
/// port 18789, bind loopback, auth.mode=token (random), reload.mode=hot,
/// device-pair publicUrl=http://127.0.0.1:18789.
enum MinimalGatewayConfig {
    static let defaultPort = 18789
    static let defaultBind = "loopback"
    static let defaultAuthMode = "token"
    static let defaultReloadMode = "hot"

    struct EnsureResult: Equatable {
        let wroteConfig: Bool
        let tokenCreated: Bool
        let port: Int
    }

    /// Ensure `~/.openclaw/openclaw.json` has local-gateway essentials.
    /// Does **not** overwrite an existing auth token. Returns whether a write
    /// happened and whether a new token was generated.
    @discardableResult
    static func ensureLocalGatewayConfig(port: Int = defaultPort) -> EnsureResult {
        let root = OpenClawConfigFile.loadDict()
        let gateway = root["gateway"] as? [String: Any] ?? [:]
        let auth = gateway["auth"] as? [String: Any] ?? [:]

        let existingToken = (auth["token"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasToken = !(existingToken?.isEmpty ?? true)

        var tokenCreated = false
        let token: String
        if let existingToken, !existingToken.isEmpty {
            token = existingToken
        } else {
            token = self.generateToken()
            tokenCreated = true
        }

        let existingMode = (auth["mode"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let authMode = (existingMode?.isEmpty == false) ? existingMode! : defaultAuthMode

        // Only fill missing / default keys; leave user customizations alone.
        let patch: [String: Any] = [
            "gateway": [
                "mode": "local",
                "port": port,
                "bind": (gateway["bind"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? defaultBind,
                "auth": [
                    "mode": authMode,
                    "token": token,
                ] as [String: Any],
                "reload": [
                    "mode": ((gateway["reload"] as? [String: Any])?["mode"] as? String)
                        .flatMap { $0.isEmpty ? nil : $0 } ?? defaultReloadMode,
                ] as [String: Any],
            ] as [String: Any],
            "plugins": [
                "entries": [
                    "device-pair": [
                        "enabled": true,
                        "config": [
                            "publicUrl": "http://127.0.0.1:\(port)",
                        ] as [String: Any],
                    ] as [String: Any],
                ] as [String: Any],
            ] as [String: Any],
            // Mark setup-managed so reinstall/cleanup can distinguish from external gateways.
            "wizard": [
                "lastRunAt": ISO8601DateFormatter().string(from: Date()),
                "lastRunVersion": "tclaw-minimal",
                "lastRunCommand": "mac-onboarding-skip-wizard",
                "lastRunMode": "local",
            ] as [String: Any],
        ]

        // If auth token already exists and the rest looks configured, still ensure
        // device-pair publicUrl + mode/port for loopback pairing parity.
        let wrote = OpenClawConfigFile.applyMergePatch(patch)
        // applyMergePatch may preserve existing gateway.auth when present (saveDict
        // guard). If we generated a brand-new token and the file had none, force
        // a write with allowGatewayAuthMutation so the first token sticks.
        if tokenCreated, !hasToken {
            var full = OpenClawConfigFile.loadDict()
            Self.applyRFC7396(into: &full, patch: patch)
            _ = OpenClawConfigFile.saveDict(full, allowGatewayAuthMutation: true)
        }

        return EnsureResult(wroteConfig: wrote || tokenCreated, tokenCreated: tokenCreated, port: port)
    }

    /// Env override: set `OPENCLAW_RUN_WIZARD=1` (or `true`/`yes`) to force the
    /// interactive gateway wizard during Mac onboarding. Default is skip.
    static func shouldRunInteractiveWizard() -> Bool {
        guard let raw = ProcessInfo.processInfo.environment["OPENCLAW_RUN_WIZARD"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !raw.isEmpty
        else {
            return false
        }
        return raw == "1" || raw == "true" || raw == "yes" || raw == "on"
    }

    private static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return Data(bytes)
                .base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// Local RFC 7396 merge (same semantics as OpenClawConfigFile.applyRFC7396)
    /// so we can force-save with allowGatewayAuthMutation when minting the first token.
    private static func applyRFC7396(into target: inout [String: Any], patch: [String: Any]) {
        for (key, value) in patch {
            if value is NSNull {
                target.removeValue(forKey: key)
            } else if let nested = value as? [String: Any] {
                if var existing = target[key] as? [String: Any] {
                    Self.applyRFC7396(into: &existing, patch: nested)
                    target[key] = existing
                } else {
                    var cleaned: [String: Any] = [:]
                    Self.applyRFC7396(into: &cleaned, patch: nested)
                    target[key] = cleaned
                }
            } else {
                target[key] = value
            }
        }
    }
}
