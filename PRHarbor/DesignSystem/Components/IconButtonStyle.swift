import SwiftUI

/// A borderless symbol button that shows a soft backing under the pointer, like toolbar buttons.
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = Size.iconButton
    var symbolSize: CGFloat = Typography.icon
    var color: Color = Palette.textSecondary

    func makeBody(configuration: Configuration) -> some View {
        IconButton(configuration: configuration, style: self)
    }

    private struct IconButton: View {
        let configuration: Configuration
        let style: IconButtonStyle
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.ui(style.symbolSize)).foregroundStyle(style.color)
                .frame(width: style.size, height: style.size)
                .background {
                    if isEnabled && (configuration.isPressed || hovering) {
                        RoundedRectangle(cornerRadius: Radius.s).fill(configuration.isPressed ? Palette.active : Palette.hover)
                    }
                }
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : Opacity.disabled)
                .onHover { hovering = $0 }
        }
    }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var icon: IconButtonStyle { IconButtonStyle() }
    static func icon(size: CGFloat, symbolSize: CGFloat, color: Color = Palette.textSecondary) -> IconButtonStyle {
        IconButtonStyle(size: size, symbolSize: symbolSize, color: color)
    }
}
