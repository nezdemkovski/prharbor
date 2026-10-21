import SwiftUI

/// The accent-filled button for the one action that matters most, such as the details card's
/// next step. `compact` draws a small capsule for chips inside the timeline.
struct PrimaryButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        if compact {
            configuration.label
                .font(.ui(Typography.caption, .semibold)).foregroundStyle(Palette.onAccent)
                .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.xxxs)
                .background(Palette.accentFill, in: Capsule())
                .controlFeedback(isPressed: configuration.isPressed)
        } else {
            let shape = RoundedRectangle(cornerRadius: Radius.m)
            configuration.label
                .font(.ui(Typography.body, .medium)).foregroundStyle(Palette.onAccent)
                .padding(.horizontal, Spacing.xxl).frame(height: Size.button)
                .background(Palette.accentFill, in: shape)
                .overlay { shape.strokeBorder(Palette.onAccent.opacity(Opacity.outline), lineWidth: 0.5) }
                .shadow(color: Palette.shadow.opacity(Opacity.shadow), radius: 0.5, y: 0.5)
                .controlFeedback(isPressed: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static var primaryCompact: PrimaryButtonStyle { PrimaryButtonStyle(compact: true) }
}
