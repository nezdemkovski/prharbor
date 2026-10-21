
import Foundation
import Defaults

extension Defaults.Keys {
    static let githubApiBaseUrl = Key<String>("githubApiBaseUrl", default: "https://api.github.com", suite: AppPreferences.storage)
    static let githubConnection = Key<GitHubConnection?>("githubConnection", default: nil, suite: AppPreferences.storage)
    static let showAssigned = Key<Bool>("showAssigned", default: false, suite: AppPreferences.storage)
    static let showCreated = Key<Bool>("showCreated", default: true, suite: AppPreferences.storage)
    static let showRequested = Key<Bool>("showRequested", default: true, suite: AppPreferences.storage)

    static let hideDrafts = Key<Bool>("hideDrafts", default: false, suite: AppPreferences.storage)
    static let notifyReviewRequested = Key<Bool>("notifyReviewRequested", default: true, suite: AppPreferences.storage)
    static let notifyAssigned = Key<Bool>("notifyAssigned", default: true, suite: AppPreferences.storage)
    static let notifyCreated = Key<Bool>("notifyCreated", default: false, suite: AppPreferences.storage)
    
    static let timelineRange = Key<Int>("timelineRange", default: 182, suite: AppPreferences.storage)
    static let freshnessThresholds = Key<[Int]>("freshnessThresholds", default: [2, 7, 21], suite: AppPreferences.storage)
    static let ownCommentsCount = Key<Bool>("ownCommentsCount", default: true, suite: AppPreferences.storage)
    static let botAccounts = Key<[String]>("botAccounts", default: ["dependabot", "github-actions", "renovate", "greptile-apps", "*[bot]"], suite: AppPreferences.storage)
    static let snoozedPulls = Key<[String: Double]>("snoozedPulls", default: [:], suite: AppPreferences.storage)
    static let snoozeActivity = Key<[String: Double]>("snoozeActivity", default: [:], suite: AppPreferences.storage)
    static let wakeOnComment = Key<Bool>("wakeOnComment", default: true, suite: AppPreferences.storage)
    static let mergedLayersStyle = Key<MergedLayersStyle>("mergedLayersStyle", default: .count, suite: AppPreferences.storage)
    static let detailHistory = Key<Bool>("detailHistory", default: false, suite: AppPreferences.storage)
    static let notifyRotting = Key<Bool>("notifyRotting", default: false, suite: AppPreferences.storage)
    static let morningSummary = Key<Bool>("morningSummary", default: false, suite: AppPreferences.storage)
    static let morningSummaryMinutes = Key<Int>("morningSummaryMinutes", default: 540, suite: AppPreferences.storage)
    static let lastMorningSummary = Key<String>("lastMorningSummary", default: "", suite: AppPreferences.storage)
    static let intelligentSearch = Key<Bool>("intelligentSearch", default: false, suite: AppPreferences.storage)
    static let intelligentMorningBrief = Key<Bool>("intelligentMorningBrief", default: false, suite: AppPreferences.storage)
    static let sortOrder = Key<SortOrder>("sortOrder", default: .updatedNewest, suite: AppPreferences.storage)
    static let collapsedRepos = Key<[String]>("collapsedRepos", default: [], suite: AppPreferences.storage)
    static let refreshRate = Key<Int>("refreshRate", default: 5, suite: AppPreferences.storage)
    static let buildType = Key<BuildType>("buildType", default: .checks, suite: AppPreferences.storage)
    static let counterType = Key<CounterType>("counterType", default: .reviewRequested, suite: AppPreferences.storage)
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

/// Everything the store and its notifications read from preferences, as one value.
/// The store asks for a fresh snapshot when it needs one; tests supply their own.
nonisolated struct PullRequestSettings: Equatable, Sendable {
    var apiBaseURL = "https://api.github.com"
    var refreshMinutes = 5
    var counterType = CounterType.reviewRequested
    var showAssigned = false, showCreated = true, showRequested = true
    var notifyAssigned = true, notifyCreated = false, notifyReviewRequested = true, notifyRotting = false
    var morningSummary = false, morningSummaryMinutes = 540, lastMorningSummary = ""
    var buildType = BuildType.checks
    var hideDrafts = false
    var thresholds = [2, 7, 21]
    var bots: [String] = []
    var ownComments = true
    var snoozed: [String: Double] = [:]
    var snoozeActivity: [String: Double] = [:]
    var wakeOnComment = true

    var refreshInterval: TimeInterval { Double(max(1, refreshMinutes)) * 60 }

    @MainActor static var saved: PullRequestSettings {
        PullRequestSettings(apiBaseURL: Defaults[.githubApiBaseUrl], refreshMinutes: Defaults[.refreshRate],
            counterType: Defaults[.counterType], showAssigned: Defaults[.showAssigned], showCreated: Defaults[.showCreated],
            showRequested: Defaults[.showRequested], notifyAssigned: Defaults[.notifyAssigned], notifyCreated: Defaults[.notifyCreated],
            notifyReviewRequested: Defaults[.notifyReviewRequested], notifyRotting: Defaults[.notifyRotting],
            morningSummary: Defaults[.morningSummary], morningSummaryMinutes: Defaults[.morningSummaryMinutes],
            lastMorningSummary: Defaults[.lastMorningSummary], buildType: Defaults[.buildType], hideDrafts: Defaults[.hideDrafts],
            thresholds: Defaults[.freshnessThresholds], bots: Defaults[.botAccounts], ownComments: Defaults[.ownCommentsCount],
            snoozed: Defaults[.snoozedPulls], snoozeActivity: Defaults[.snoozeActivity], wakeOnComment: Defaults[.wakeOnComment])
    }

    /// The query a refresh needs: visible categories plus whatever notifications and the counter read.
    func scope(username: String) -> PullSnapshotScope {
        let fetchAssigned = showAssigned || notifyAssigned || counterType == .assigned
        let fetchCreated = showCreated || notifyRotting || morningSummary || notifyCreated
            || counterType == .rotting || counterType == .created
        let fetchRequested = showRequested || morningSummary || notifyReviewRequested
            || counterType == .waitingOnYou || counterType == .rotting || counterType == .reviewRequested
        return PullSnapshotScope(username: username, baseURL: apiBaseURL, buildType: buildType, hideDrafts: hideDrafts,
                                 assigned: fetchAssigned, created: fetchCreated, requested: fetchRequested)
    }
}

