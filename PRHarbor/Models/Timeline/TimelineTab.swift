import Foundation

nonisolated enum TimelineTab: String, CaseIterable, Identifiable, Sendable {
    case all = "All", mine = "Mine", reviewing = "Reviewing"
    var id: Self { self }
}
