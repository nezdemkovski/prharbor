import Foundation

nonisolated enum TimelineTab: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case mine = "Mine"
    case reviewing = "Reviewing"
    var id: Self { self }
}
