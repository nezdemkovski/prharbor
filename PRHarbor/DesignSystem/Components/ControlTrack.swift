import SwiftUI

/// The recessed track that holds segments or chips.
struct ControlTrack: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Spacing.xxs)
            .background(Palette.track, in: RoundedRectangle(cornerRadius: Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Palette.line))
    }
}

extension View {
    func controlTrack() -> some View { modifier(ControlTrack()) }
}
