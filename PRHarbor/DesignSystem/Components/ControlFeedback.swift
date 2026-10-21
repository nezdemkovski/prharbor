import SwiftUI

/// How a control responds to the pointer: it brightens a little under it and darkens while pressed.
struct ControlFeedback: ViewModifier {
    let isPressed: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .brightness(!isEnabled ? 0 : isPressed ? Feedback.pressedBrightness : hovering ? Feedback.hoverBrightness : 0)
            .opacity(isEnabled ? 1 : Opacity.disabled)
            .onHover { hovering = $0 }
    }
}

extension View {
    func controlFeedback(isPressed: Bool) -> some View { modifier(ControlFeedback(isPressed: isPressed)) }
}
