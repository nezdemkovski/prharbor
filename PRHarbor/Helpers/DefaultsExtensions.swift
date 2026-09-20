
import Foundation
import Defaults

extension Defaults.Keys {
    static let githubApiBaseUrl = Key<String>("githubApiBaseUrl", default: "https://api.github.com")
    static let githubUsername = Key<String>("githubUsername", default: "")
    static let showAssigned = Key<Bool>("showAssigned", default: false)
    static let showCreated = Key<Bool>("showCreated", default: true)
    static let showRequested = Key<Bool>("showRequested", default: true)

    static let showAvatar = Key<Bool>("showAvatar", default: true)
    static let showLabels = Key<Bool>("showLabels", default: true)
    static let clickOpensLink = Key<Bool>("clickOpensLink", default: false)
    static let showUnreadDot = Key<Bool>("showUnreadDot", default: true)
    static let showLinesChanged = Key<Bool>("showLinesChanged", default: true)
    static let showApprovals = Key<Bool>("showApprovals", default: true)
    static let hideDrafts = Key<Bool>("hideDrafts", default: false)
    static let notifyReviewRequested = Key<Bool>("notifyReviewRequested", default: true)
    static let notifyAssigned = Key<Bool>("notifyAssigned", default: true)
    static let notifyCreated = Key<Bool>("notifyCreated", default: false)
    
    static let staleDays = Key<Int>("staleDays", default: 7)
    static let sortOrder = Key<SortOrder>("sortOrder", default: .updatedNewest)
    static let groupByRepo = Key<Bool>("groupByRepo", default: true)
    static let collapsedRepos = Key<[String]>("collapsedRepos", default: [])
    static let refreshRate = Key<Int>("refreshRate", default: 5)
    static let buildType = Key<BuildType>("buildType", default: .checks)
    static let counterType = Key<CounterType>("counterType", default: .reviewRequested)
}

extension KeychainKeys {
    static let githubToken = KeychainKey("githubToken")
}

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

nonisolated enum BuildType: String, Defaults.Serializable, CaseIterable, Identifiable, Sendable {
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

nonisolated enum CounterType: String, Defaults.Serializable, CaseIterable, Identifiable, Sendable {
    case assigned
    case created
    case reviewRequested
    case none

    var id: Self { self }

    var description: String {
        switch self {
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
