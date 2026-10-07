
import SwiftUI
private func adaptive(dark: NSColor, light: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    })
}

enum Theme {
    static let cardBackground = adaptive(
        dark: .white.withAlphaComponent(0.05),
        light: .black.withAlphaComponent(0.03)
    )
    static let unread = Color(nsColor: NSColor(red: 0.35, green: 0.55, blue: 1.0, alpha: 1.0))
    static let success = Color(nsColor: NSColor(red: 0.30, green: 0.78, blue: 0.45, alpha: 1.0))
    static let failure = Color(nsColor: NSColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 1.0))
    static let neutral = Color(nsColor: NSColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 1.0))
    static let stale = Color(nsColor: NSColor(red: 0.95, green: 0.60, blue: 0.20, alpha: 1.0))
    static let panelWidth = TimelineMetrics.panelWidth
    static let panelHeight: CGFloat = 750
    static let cardCornerRadius: CGFloat = 10
    static let contentPadding: CGFloat = 12
}

/// The prototype's shared colors, resolved for the native view's appearance.
enum TimelineStyle {
    static func color(_ light: Int, _ dark: Int? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? (dark ?? light) : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, alpha: 1)
        })
    }
    static let panel = color(0xffffff, 0x1a1b1f)
    static let line = color(0xeef0f3, 0x26282d)
    static let strong = color(0xe3e6eb, 0x2f3237)
    static let text = color(0x16181c, 0xeceef1)
    static let muted = color(0x858c96, 0x8b919a)
    static let faint = color(0xb5bbc4, 0x5b6068)
    static let track = color(0xf8f9fa, 0x1f2125)
    static let active = color(0xe3e6eb, 0x33363c)
    static let hover = color(0xf6f7f9, 0x222428)
    static let accent = color(0x3d82f6, 0x5b9cff)
    static let accentSoft = color(0xe9f1fe, 0x1d2a40)
}
