import SwiftUI

/// A button drawn as its color on a light wash of the same color: the "/" key and the sync badge.
struct TintedButtonStyle: ButtonStyle {
    var color: Color = Palette.accent
    var background: Color = Palette.accentSoft
    var kind: Kind = .key

    enum Kind { case key, capsule }

    func makeBody(configuration: Configuration) -> some View {
        Group {
            switch kind {
            case .key:
                configuration.label
                    .font(.ui(Typography.body, .semibold))
                    .frame(width: Size.button, height: Size.button)
                    .background(background, in: RoundedRectangle(cornerRadius: Radius.control))
            case .capsule:
                configuration.label
                    .font(.ui(Typography.subheadline, .semibold))
                    .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.xxs)
                    .background(background, in: Capsule())
            }
        }
        .foregroundStyle(color)
        .contentShape(Rectangle())
        .controlFeedback(isPressed: configuration.isPressed)
    }
}

extension ButtonStyle where Self == TintedButtonStyle {
    static var key: TintedButtonStyle { TintedButtonStyle() }
    static func badge(_ color: Color, background: Color) -> TintedButtonStyle {
        TintedButtonStyle(color: color, background: background, kind: .capsule)
    }
}
