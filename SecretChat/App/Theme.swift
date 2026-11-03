import SwiftUI

/// SecretChat look: a dark, night-time palette with an emerald "secure" accent. Orange is reserved
/// for anything that touches the internet, so "leaves the phone" always stands out.
enum Theme {
    static let appName = "SecretChat"

    // Backgrounds
    static let background = Color(red: 0.027, green: 0.043, blue: 0.071)        // #070B12
    static let backgroundTop = Color(red: 0.055, green: 0.090, blue: 0.149)     // #0E1726
    static let surface = Color(red: 0.071, green: 0.102, blue: 0.165)           // #121A2A
    static let elevated = Color(red: 0.094, green: 0.137, blue: 0.220)          // #182338
    static let separator = Color.white.opacity(0.08)

    // Accent
    static let accent = Color(red: 0.169, green: 0.851, blue: 0.627)            // #2BD9A0
    static let accentDeep = Color(red: 0.075, green: 0.486, blue: 0.431)        // #137C6E
    static let internet = Color.orange

    // Text
    static let textPrimary = Color(red: 0.910, green: 0.933, blue: 0.965)       // #E8EEF6
    static let textSecondary = Color(red: 0.541, green: 0.592, blue: 0.671)     // #8A97AB

    static let userBubble = LinearGradient(
        colors: [Color(red: 0.118, green: 0.620, blue: 0.478), accentDeep],     // #1E9E7A → #137C6E
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let screenGradient = LinearGradient(colors: [backgroundTop, background], startPoint: .top, endPoint: .bottom)
}

extension View {
    /// Night background behind lists, forms and scroll views.
    func secretBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.screenGradient.ignoresSafeArea())
    }
}

/// "🔒 W pełni offline" / "🌐 Internet na żądanie" — the app's privacy state at a glance.
struct PrivacyBadge: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let online = settings.webSearchEnabled
        Label(online ? "Internet na żądanie" : "W pełni offline", systemImage: online ? "globe" : "lock.fill")
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(online ? Theme.internet : Theme.accent)
            .background((online ? Theme.internet : Theme.accent).opacity(0.14), in: .capsule)
            .overlay(Capsule().strokeBorder((online ? Theme.internet : Theme.accent).opacity(0.35)))
            .accessibilityLabel(online ? "Wyszukiwanie w internecie włączone, tylko za zgodą" : "Aplikacja działa w pełni offline")
    }
}
