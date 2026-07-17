import Foundation

/// Debug/QA language override for the macOS app.
///
/// Follows system preferred language by default. Set env `OPENCLAW_LANGUAGE`
/// (e.g. `zh-CN`, `zh-Hans`, `zh-TW`, `en`) before launch to force a locale —
/// mirrors Windows `OPENCLAW_LANGUAGE` (docs/MAC_PORT_HANDOFF.md §4 / §7).
///
/// Must run before any SwiftUI views resolve `Text` / `LocalizedStringKey`.
enum LanguageOverride {
    static func applyIfNeeded() {
        guard let raw = ProcessInfo.processInfo.environment["OPENCLAW_LANGUAGE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else {
            return
        }
        let code = Self.normalize(raw)
        // AppleLanguages is read once early by Foundation; set before UI.
        UserDefaults.standard.set([code], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
    }

    /// Map common Windows/CLI forms onto Apple language codes.
    static func normalize(_ raw: String) -> String {
        let lower = raw.replacingOccurrences(of: "_", with: "-").lowercased()
        switch lower {
        case "zh", "zh-cn", "zh-hans", "zh-hans-cn", "cn", "chinese":
            return "zh-Hans"
        case "zh-tw", "zh-hant", "zh-hk", "zh-mo", "tw":
            return "zh-Hant"
        case "en", "en-us", "en-gb", "english":
            return "en"
        default:
            // Pass through (e.g. "ja", "ko") — Foundation ignores unknown codes.
            return raw
        }
    }
}
