import SwiftUI

struct TimelineAvatar: View {
    let person: User?
    let size: CGFloat
    var miniature = false
    var body: some View {
        Group {
            if let url = person?.avatarUrl { AsyncAvatarView(url: url) }
            else {
                let login = person?.login ?? "ghost"
                ZStack {
                    Circle().fill(miniature ? AnyShapeStyle(Palette.track) : AnyShapeStyle(gradient(login)))
                    Text(String(login.prefix(1)).uppercased())
                        .font(.ui(miniature ? Typography.nano : Typography.callout, .semibold))
                        .foregroundStyle(miniature ? Palette.textSecondary : AvatarColors.initials(for: login))
                }
            }
        }.frame(width: size, height: size).clipShape(Circle())
    }
    private func gradient(_ login: String) -> LinearGradient {
        let hue = AvatarColors.hue(for: login)
        return LinearGradient(colors: [Color(hue: hue, saturation: 0.7, brightness: 0.9), Color(hue: (hue + 40.0 / 360).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Generated avatar colors. Initials use white or near-black, whichever contrasts more with
/// the gradient, so every hue reaches at least 4.5:1.
nonisolated enum AvatarColors {
    static func hue(for login: String) -> Double {
        Double(login.utf16.reduce(0) { ($0 * 31 + Int($1)) % 360 }) / 360
    }

    static func initials(for login: String) -> Color {
        // The gradient's middle: brightness 0.85 between its two stops.
        let background = NSColor(hue: hue(for: login), saturation: 0.7, brightness: 0.85, alpha: 1).usingColorSpace(.sRGB) ?? .gray
        func channel(_ value: CGFloat) -> CGFloat { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * channel(background.redComponent) + 0.7152 * channel(background.greenComponent) + 0.0722 * channel(background.blueComponent)
        let onWhite = 1.05 / (luminance + 0.05)
        let onDark = (luminance + 0.05) / (0.0137 + 0.05) // relative luminance of Palette.ink
        return onWhite >= onDark ? Palette.onAccent : Palette.color(Palette.ink)
    }
}
