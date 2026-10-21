import Defaults
import Foundation

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
        PullRequestSettings(
            apiBaseURL: Defaults[.githubApiBaseUrl], refreshMinutes: Defaults[.refreshRate],
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
        let fetchCreated =
            showCreated || notifyRotting || morningSummary || notifyCreated
            || counterType == .rotting || counterType == .created
        let fetchRequested =
            showRequested || morningSummary || notifyReviewRequested
            || counterType == .waitingOnYou || counterType == .rotting || counterType == .reviewRequested
        return PullSnapshotScope(
            username: username, baseURL: apiBaseURL, buildType: buildType, hideDrafts: hideDrafts,
            assigned: fetchAssigned, created: fetchCreated, requested: fetchRequested)
    }
}
