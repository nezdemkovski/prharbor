import SwiftUI

/// Makes a view part of the timeline's pointer surface: on the track column the pointer shows
/// its date, a drag selects a range of quiet time, and a click clears the range. Buttons and
/// rows inside take their own clicks first. Apply it where x is measured from the panel's
/// leading edge, after any horizontal padding.
struct TimelinePointer: ViewModifier {
    let interaction: TimelineInteraction
    let selectRange: (ClosedRange<Double>?) -> Void
    let clearRange: () -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard !interaction.isScrolling else { return }
                switch phase {
                case .active(let point): interaction.hover(at: point.x)
                case .ended: interaction.endHover()
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: Layout.brushDragThreshold)
                    .onChanged { interaction.drag(from: $0.startLocation.x, to: $0.location.x) }
                    .onEnded { _ in interaction.endDrag(selectRange) }
            )
            .onTapGesture(coordinateSpace: .local) { location in
                if interaction.isOnTrack(location.x) { clearRange() }
            }
    }
}

extension View {
    func timelinePointer(
        _ interaction: TimelineInteraction, selectRange: @escaping (ClosedRange<Double>?) -> Void, clearRange: @escaping () -> Void
    ) -> some View {
        modifier(TimelinePointer(interaction: interaction, selectRange: selectRange, clearRange: clearRange))
    }
}
