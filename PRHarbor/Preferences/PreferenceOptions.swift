import Defaults
import Foundation

nonisolated enum SortOrder: String, Defaults.Serializable, CaseIterable, Identifiable, Sendable {
    case updatedNewest
    case updatedOldest
    case createdNewest
    case createdOldest

    var id: Self { self }

    var description: String {
        switch self {
        case .updatedNewest: return "Updated (Newest)"
        case .updatedOldest: return "Updated (Oldest)"
        case .createdNewest: return "Created (Newest)"
        case .createdOldest: return "Created (Oldest)"
        }
    }
}

nonisolated enum BuildType: String, Codable, Defaults.Serializable, Defaults.PreferRawRepresentable, CaseIterable, Identifiable, Sendable {
    case checks
    case commitStatus
    case none

    var id: Self { self }

    var description: String {
        switch self {
        case .checks:
            return "GitHub Actions"
        case .commitStatus:
            return "Status Checks"
        case .none:
            return "Hidden"
        }
    }
}

/// How the footer of a stack lists its merged layers. Stored as its raw value, as before it was an enum.
nonisolated enum MergedLayersStyle: Int, Defaults.Serializable, CaseIterable, Identifiable, Sendable {
    case count, numbers, hidden
    var id: Self { self }
}

nonisolated enum CounterType: String, Defaults.Serializable, CaseIterable, Identifiable, Sendable {
    case rotting
    case waitingOnYou
    case assigned
    case created
    case reviewRequested
    case none

    var id: Self { self }

    var description: String {
        switch self {
        case .rotting: return "Rotting"
        case .waitingOnYou: return "Waiting on you"
        case .assigned:
            return "Assigned"
        case .created:
            return "My PRs"
        case .reviewRequested:
            return "Review Requested"
        case .none:
            return "None"
        }
    }
}

extension CounterType {
    /// The number the menu bar shows next to the icon.
    nonisolated func count(items: [TimelineItem], assigned: Int, created: Int, requested: Int) -> Int {
        switch self {
        case .rotting: items.filter { $0.hasKnownQuietPeriod && $0.freshness == .rotting && $0.snoozedUntil == nil }.count
        case .waitingOnYou: TimelineNotificationPolicy.waitingForReview(items).count
        case .assigned: assigned
        case .created: created
        case .reviewRequested: requested
        case .none: 0
        }
    }
}
