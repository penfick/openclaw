import Foundation

/// Product-facing brand strings.
///
/// Display name is **TClaw** (enterprise fork branding, aligned with Windows).
/// Internal identifiers stay `OpenClaw` / `openclaw` / `ai.openclaw.*` for gateway
/// compatibility — see docs/MAC_PORT_HANDOFF.md §3.
enum Brand {
    /// User-visible product name (About, window titles, menu bar, onboarding).
    static let displayName = "TClaw"

    /// Short description used on the About page.
    static let tagline =
        "Menu bar companion for notifications, screenshots, and privileged agent actions."

    /// Copyright line on About.
    static let copyright = "© 2026 TClaw — MIT License."
}
