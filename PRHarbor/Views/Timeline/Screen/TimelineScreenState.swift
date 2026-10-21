import Foundation

nonisolated struct TimelineScreenInput: Equatable {
    /// Already projected items, usually the store's own array, so unchanged data compares by identity.
    var items: [TimelineItem]
    var sources: PullSources = .all
    var now: Date
    var thresholds: [Int]
    var sortOrder: SortOrder
    var collapsed: [String]
    var intelligentSearch: Bool
}

/// All derived screen values are replaced in a single publication. Focus and
/// pointer/scroll gestures remain local to the view.
nonisolated struct TimelineScreenSnapshot: Sendable {
    let items: [TimelineItem]
    let tabItems: [TimelineItem]
    let presentation: TimelinePresentation
    let brief: MorningBriefSnapshot
    let searchRequest: IntelligenceSearchRequest
    let tab: TimelineTab
    let query: String
    let effectiveQuery: String
    let brush: ClosedRange<Double>?
    let zone: Freshness?
    let selection: String?
    let isSearching: Bool
    let understood: Bool
    let searchMessage: String?

    var selected: TimelineItem? { selection.flatMap { presentation.itemsByID[$0] } }
}
