import Foundation
import Testing

@testable import PRHarbor

@Suite("Timeline interaction")
@MainActor
struct TimelineInteractionTests {
    private func x(age: Double, on scale: TimelineScale) -> CGFloat {
        TimelineMetrics.trackOrigin + scale.position(age: age) * TimelineMetrics.trackWidth
    }

    @Test(arguments: [TimelineScale(days: 30), TimelineScale(days: 182)])
    func aSelectionEndsOnTheWholeDaysUnderThePointer(scale: TimelineScale) {
        let interaction = TimelineInteraction()
        interaction.scale = scale
        // Ages between the old fixed stops (3, 5, 7, 10, 14, 21) used to jump to the nearest stop.
        interaction.drag(from: x(age: 17.2, on: scale), to: x(age: 4.4, on: scale))
        #expect(interaction.dragging == 4...17)
        interaction.drag(from: x(age: 11.6, on: scale), to: x(age: 0, on: scale))
        #expect(interaction.dragging == 0...12)
    }

    @Test func dragToTheOldestEdgeSelectsEverythingOlder() {
        let scale = TimelineScale(days: 30)
        let interaction = TimelineInteraction()
        interaction.scale = scale
        interaction.drag(from: x(age: 8, on: scale), to: x(age: 30, on: scale))
        #expect(interaction.dragging == 8...Double.infinity)
    }

    @Test func onlyTheTrackColumnRespondsToThePointer() {
        let interaction = TimelineInteraction()
        #expect(!interaction.isOnTrack(TimelineMetrics.trackOrigin - 1))
        #expect(interaction.isOnTrack(TimelineMetrics.trackOrigin))
        #expect(interaction.isOnTrack(TimelineMetrics.trackOrigin + TimelineMetrics.trackWidth))
        interaction.hover(at: TimelineMetrics.trackOrigin + 10)
        #expect(interaction.cursorAge != nil)
        interaction.hover(at: 20)
        #expect(interaction.cursorAge == nil)
    }

    @Test func aDragStartedOnTheLabelsSelectsNothing() {
        let interaction = TimelineInteraction()
        var selected: [ClosedRange<Double>?] = []
        interaction.drag(from: 40, to: TimelineMetrics.trackOrigin + 200)
        interaction.endDrag { selected.append($0) }
        #expect(selected.isEmpty)
        interaction.drag(from: TimelineMetrics.trackOrigin + 400, to: TimelineMetrics.trackOrigin + 200)
        #expect(interaction.dragging != nil)
        interaction.endDrag { selected.append($0) }
        #expect(selected.count == 1)
        #expect(interaction.dragging == nil)
    }
}
