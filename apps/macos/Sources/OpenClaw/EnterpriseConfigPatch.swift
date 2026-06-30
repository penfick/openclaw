import Foundation

// Enterprise config helpers.
//
// Enterprise features (Models / MCP / Skills market / OA) read and write openclaw config via
// DIRECT file access to ~/.openclaw/openclaw.json — NOT the config.patch / config.get RPC.
// The gateway chokidar-watches this file and async-reloads ~1s after an external write, so a
// direct read-modify-write returns instantly instead of blocking on the gateway's synchronous
// reload (config.patch ~4.5s, config.get ~0.5-1.2s). This mirrors the Windows port's
// OpenClawConfigFile.cs after its perf pass; see mac-port-recent-updates.md §1.
//
// Patches are RFC 7396 JSON Merge Patch (same semantics as config.patch), so all existing
// patch-construction code (buildNestedPatch, the nested dicts in Models/MCP) is unchanged —
// only where the patch is applied changed (file vs RPC).
//
// Hard rules (still apply to the patch shape):
//  - null (NSNull) = delete key (legal); a LEAF null inside an object is a schema violation.
//    Direct-file writes have no synchronous schema check (the gateway validates at reload ~1s
//    later and skips if invalid), but keep the same discipline: only write fields that exist.
//  - batch related changes into ONE patch when convenient (fewer read-modify-write cycles).

/// Dotted config paths used by enterprise features (gateway 2026.6.5).
enum EnterpriseConfigPaths {
    static let providers = "models.providers"
    static let allowlist = "agents.defaults.models"
    static let defaultModel = "agents.defaults.model.primary"
    static let mcpServers = "mcp.servers"
    static let legacyAcpy = "plugins.entries.acpx"
    static let skillsInstall = "skills.install"
}

@MainActor
enum EnterpriseConfigPatch {

    /// Read the current config root directly from ~/.openclaw/openclaw.json (instant), as plain
    /// Foundation types. Replaces config.get RPC. Returns [:] only if the file is missing/invalid.
    static func readConfig() async -> [String: Any]? {
        OpenClawConfigFile.loadDict()
    }

    /// Apply an RFC 7396 merge patch directly to the config file (instant; the gateway
    /// hot-reloads ~1s later). Replaces config.patch RPC. Throws only if the atomic write fails
    /// or OpenClawConfigFile's suspicious-write guard rejects it.
    static func writePatch(_ patch: [String: Any]) async throws {
        let ok = OpenClawConfigFile.applyMergePatch(patch)
        if !ok {
            throw NSError(
                domain: "OpenClawConfig",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "配置写入失败，请稍后重试。"])
        }
    }

    /// Build a nested merge-patch from a dotted parent path + final key + value.
    /// value == nil → NSNull → key deletion (RFC 7396 null semantics).
    static func buildNestedPatch(parentPath: String, finalKey: String, value: Any?) -> [String: Any] {
        let leaf: Any
        if let value { leaf = value } else { leaf = NSNull() }
        var node: [String: Any] = [finalKey: leaf]
        for seg in parentPath.split(separator: ".").reversed() {
            node = [String(seg): node]
        }
        return node
    }

    /// Walk a dotted path through a Foundation config dict, returning the node or nil.
    /// Mirrors Windows McpConfig.Walk.
    static func walk(_ root: Any?, dotPath: String) -> Any? {
        var current: Any? = root
        for seg in dotPath.split(separator: ".") {
            guard let dict = current as? [String: Any], let next = dict[String(seg)] else {
                return nil
            }
            current = next
        }
        return current
    }

    /// Translate gateway / file-write error messages to friendly Chinese.
    /// (The config.patch rate-limit path is largely vestigial now that writes are direct-file,
    /// but kept for any residual gateway errors surfaced by callers.)
    static func friendlyConfigError(_ message: String) -> String {
        let lower = message.lowercased()
        guard lower.contains("rate limit") || lower.contains("retry after") else {
            return message
        }
        if let regex = try? NSRegularExpression(pattern: "retry after\\s*(\\d+)\\s*s", options: .caseInsensitive) {
            let ns = message as NSString
            if let match = regex.firstMatch(in: message, range: NSRange(location: 0, length: ns.length)),
               match.numberOfRanges >= 2
            {
                let seconds = ns.substring(with: match.range(at: 1))
                return "网关配置写入限流，请等待 \(seconds) 秒后重试。"
            }
        }
        return "网关配置写入限流，请稍候再试。"
    }
}
