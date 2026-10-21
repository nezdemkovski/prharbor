import Foundation

nonisolated enum TimelineTab: String, CaseIterable, Identifiable, Sendable {
    case all = "All", mine = "Mine", reviewing = "Reviewing"
    var id: Self { self }
}

nonisolated enum Freshness: String, CaseIterable, Identifiable, Sendable {
    case fresh, aging, stale, rotting
    var id: Self { self }
    func contains(_ days: Double, thresholds: [Int]) -> Bool {
        let t = TimelinePolicy.validThresholds(thresholds)
        switch self {
        case .fresh: return days < Double(t[0])
        case .aging: return days >= Double(t[0]) && days < Double(t[1])
        case .stale: return days >= Double(t[1]) && days < Double(t[2])
        case .rotting: return days >= Double(t[2])
        }
    }
}
