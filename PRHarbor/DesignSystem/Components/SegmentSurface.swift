import SwiftUI

/// The raised surface of a selected segment or chip, and the pointer highlight of the others.
struct SegmentSurface: View {
    let isSelected: Bool
    let isPressed: Bool
    let hovering: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.s)
        if isSelected {
            shape.fill(Palette.raised)
                .shadow(color: Palette.shadow.opacity(Opacity.shadowSoft), radius: 1, y: 1)
                .overlay(shape.strokeBorder(Palette.strong, lineWidth: Stroke.hairline))
        } else if isPressed || hovering {
            shape.fill(isPressed ? Palette.active : Palette.hover)
        }
    }
}
