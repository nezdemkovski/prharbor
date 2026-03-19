
import SwiftUI
private func adaptive(dark: NSColor, light: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    })
}

enum Theme {
    static let panelMaterial: Material = .thickMaterial

    static let cardBackground = adaptive(
        dark: .white.withAlphaComponent(0.05),
        light: .black.withAlphaComponent(0.03)
    )

    static let hoverBackground = adaptive(
        dark: .white.withAlphaComponent(0.07),
        light: .black.withAlphaComponent(0.05)
    )

    static let selectedBackground = adaptive(
        dark: .white.withAlphaComponent(0.10),
        light: .black.withAlphaComponent(0.07)
    )

    static let groupedBackground = adaptive(
        dark: .white.withAlphaComponent(0.035),
        light: .black.withAlphaComponent(0.025)
    )

    static let labelBackgroundOpacity: Double = 0.18

    static let tabSelected = adaptive(
        dark: .white.withAlphaComponent(0.14),
        light: .black.withAlphaComponent(0.10)
    )
    static let unread = Color(nsColor: NSColor(red: 0.35, green: 0.55, blue: 1.0, alpha: 1.0))
    static let success = Color(nsColor: NSColor(red: 0.30, green: 0.78, blue: 0.45, alpha: 1.0))
    static let failure = Color(nsColor: NSColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 1.0))
    static let pending = Color(nsColor: NSColor(red: 0.95, green: 0.75, blue: 0.25, alpha: 1.0))
    static let neutral = Color(nsColor: NSColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 1.0))
    static let stale = Color(nsColor: NSColor(red: 0.95, green: 0.60, blue: 0.20, alpha: 1.0))
    static let draft = adaptive(
        dark: .white.withAlphaComponent(0.35),
        light: .black.withAlphaComponent(0.30)
    )


    static let panelWidth: CGFloat = 440
    static let panelHeight: CGFloat = 520

    static let avatarSize: CGFloat = 30
    static let unreadDotSize: CGFloat = 7
    static let ciDotSize: CGFloat = 8
    static let ciDotInlineSize: CGFloat = 6
    static let cornerRadius: CGFloat = 8
    static let cardCornerRadius: CGFloat = 10
    static let rowCornerRadius: CGFloat = 8
    static let headerPaddingH: CGFloat = 16
    static let headerPaddingV: CGFloat = 10
    static let rowPaddingH: CGFloat = 12
    static let rowPaddingV: CGFloat = 8
    static let contentPadding: CGFloat = 12
    static let settingsPaddingH: CGFloat = 14
    static let settingsPaddingV: CGFloat = 10
}
