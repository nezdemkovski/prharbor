import Foundation
import Observation

/// The pointer on the timeline: where it hovers, the range being dragged, and whether a click
/// lands on the track column. Positions are x from the panel's leading edge. Only the axis and
/// the grid observe it, so pointer movement never invalidates rows.
@Observable
final class TimelineInteraction {
    var cursorAge: Double?
    var dragging: ClosedRange<Double>?
    @ObservationIgnored private(set) var brushing = false
    @ObservationIgnored var isScrolling = false
    @ObservationIgnored var scale = TimelineScale(days: 182)
    private let width = TimelineMetrics.trackWidth
    private let trackOrigin = TimelineMetrics.trackOrigin

    func isOnTrack(_ x: CGFloat) -> Bool {
        (trackOrigin...(trackOrigin + width)).contains(x)
    }

    func hover(at x: CGFloat) {
        let value = isOnTrack(x) ? scale.age(at: (x - trackOrigin) / width) : nil
        // A subpixel mouse move must not invalidate an identical displayed position.
        if value != cursorAge { cursorAge = value }
    }

    func endHover() { cursorAge = nil }

    /// Follows a drag that started on the track; edges land on whole days.
    func drag(from startX: CGFloat, to endX: CGFloat) {
        guard isOnTrack(startX) else { return }
        brushing = true
        let first = scale.age(at: (startX - trackOrigin) / width)
        let second = scale.age(at: (endX - trackOrigin) / width)
        let lower = scale.wholeDay(min(first, second))
        let upper = scale.wholeDay(max(first, second))
        let value: ClosedRange<Double>? = lower == upper ? nil : lower...(upper >= Double(scale.days) ? .infinity : upper)
        if dragging != value { dragging = value }
    }

    /// Ends a drag, handing the selected range to `select` when the drag was on the track.
    func endDrag(_ select: (ClosedRange<Double>?) -> Void) {
        if brushing { select(dragging) }
        dragging = nil
        brushing = false
    }
}
