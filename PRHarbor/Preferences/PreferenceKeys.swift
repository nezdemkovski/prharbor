import Defaults
import Foundation

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
