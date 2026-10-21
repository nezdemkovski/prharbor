import Foundation
import Observation

/// Only axis/grid depend on pointer movement; rows and data preparation do not.
@Observable
final class TimelineInteraction {
    var cursorAge: Double?
    var dragging: ClosedRange<Double>?
    @ObservationIgnored var brushing = false
    @ObservationIgnored var isScrolling = false
    @ObservationIgnored var scale = TimelineScale(days: 182)
    private let width = TimelineMetrics.panelWidth - 2 * TimelineMetrics.inset - TimelineMetrics.labelWidth
    private let trackOrigin = TimelineMetrics.inset + TimelineMetrics.labelWidth
    func hover(at x: CGFloat) {
        // Gestures are attached after padding, so their coordinates include the inset.
        let position = x - trackOrigin
        let value = position >= 0 && position <= width ? scale.age(at: position / width) : nil
        // A subpixel mouse move must not invalidate an identical displayed position.
        if value != cursorAge { cursorAge = value }
    }
    func drag(from startX: CGFloat, to endX: CGFloat, scale: TimelineScale) {
        let start = startX - trackOrigin
        guard start >= 0, start <= width else { return }
        brushing = true
        let first = scale.age(at: start / width)
        let second = scale.age(at: (endX - trackOrigin) / width)
        let lower = scale.snappedAge(min(first, second)), upper = scale.snappedAge(max(first, second))
        let value: ClosedRange<Double>? = lower == upper ? nil : lower...(upper >= Double(scale.days) ? .infinity : upper)
        if dragging != value { dragging = value }
    }
    func endDrag() { dragging = nil; brushing = false }
}
