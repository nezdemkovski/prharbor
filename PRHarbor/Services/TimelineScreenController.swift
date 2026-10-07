import Foundation
import Combine

nonisolated struct TimelineScreenInput: Equatable {
    let data: TimelineInput
    let previewItems: [TimelineItem]?
    let sortOrder: SortOrder
    let collapsed: [String]
    let intelligentSearch: Bool
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

@MainActor final class TimelineScreenController: ObservableObject {
    @Published private(set) var snapshot: TimelineScreenSnapshot
    private var input: TimelineScreenInput?
    private var items: [TimelineItem] = []
    private var context = IntelligenceSearchContext(items: [])
    private var brief = MorningBriefSnapshot(items: [], now: .now)
    private var tab: TimelineTab = .all
    private var query = ""
    private var collapsed: [String] = []
    private var selection: String?
    private var appliedQuery = ""
    private var completedRequest: IntelligenceSearchRequest?
    private var searchRevision = UUID()
    private var isSearching = false
    private var understood = false
    private var searchMessage: String?
    private struct PresentationKey: Equatable {
        let tab: TimelineTab
        let query: String
        let sortOrder: SortOrder
        let collapsed: [String]
    }
    private var presentationKey: PresentationKey?

    init() {
        snapshot = TimelineScreenSnapshot(items: [], tabItems: [], presentation: TimelinePresentation(),
            brief: MorningBriefSnapshot(items: [], now: .now), searchRequest: IntelligenceSearchRequest(text: "", enabled: false, context: IntelligenceSearchContext(items: []), hasLiteralMatches: false),
            tab: .all, query: "", effectiveQuery: "", brush: nil, zone: nil, selection: nil,
            isSearching: false, understood: false, searchMessage: nil)
    }

    func update(_ value: TimelineScreenInput) {
        guard value != input else { return }
        if input?.data != value.data || input?.previewItems != value.previewItems {
            items = value.previewItems ?? value.data.makeItems()
            context = IntelligenceSearchContext(items: items)
            brief = MorningBriefSnapshot(items: items, now: value.data.now)
            presentationKey = nil
        }
        input = value
        collapsed = value.collapsed
        publish()
    }

    func setTab(_ value: TimelineTab) { tab = value; publish() }
    func setQuery(_ value: String) { query = value; publish() }
    func clearQuery() { setQuery("") }

    func zoneRange(_ zone: Freshness) -> ClosedRange<Double> {
        let thresholds = TimelinePolicy.validThresholds(input?.data.thresholds ?? [2, 7, 21]).map(Double.init)
        switch zone {
        case .fresh: return 0...thresholds[0]
        case .aging: return thresholds[0]...thresholds[1]
        case .stale: return thresholds[1]...thresholds[2]
        case .rotting: return thresholds[2]...Double.infinity
        }
    }
    func setZone(_ value: Freshness?) { writeIdle(value.map(zoneRange)) }
    func writeIdle(_ value: ClosedRange<Double>?) {
        var tokens = query.split(whereSeparator: \.isWhitespace).map(String.init).filter { TimelinePolicy.idleRange($0) == nil }
        if let value {
            tokens.append(value.upperBound.isFinite ? "idle:\(Int(value.lowerBound))d-\(Int(value.upperBound))d" : "idle:\(Int(value.lowerBound))d+")
        }
        setQuery(tokens.joined(separator: " "))
    }

    @discardableResult func toggleCollapsed(_ name: String) -> [String] {
        if collapsed.contains(name) { collapsed.removeAll { $0 == name } } else { collapsed.append(name) }
        publish()
        return collapsed
    }
    @discardableResult func select(_ id: String) -> [String]? {
        guard let item = snapshot.presentation.itemsByID[id] else { return nil }
        if !snapshot.presentation.visibleIDs.contains(id) && !snapshot.presentation.navigationIDs.contains(id) {
            tab = .all; query = ""
        }
        collapsed.removeAll { $0 == item.pull.repository.nameWithOwner || $0 == "stack:" + (item.pull.stack?.id ?? "") }
        if item.isBot, !collapsed.contains("Bots") { collapsed.append("Bots") }
        selection = id
        publish()
        return collapsed
    }
    func move(_ delta: Int) {
        let ids = snapshot.presentation.navigationIDs
        guard !ids.isEmpty else { return }
        let index = selection.flatMap { ids.firstIndex(of: $0) } ?? (delta > 0 ? -1 : ids.count)
        selection = ids[min(ids.count - 1, max(0, index + delta))]
        publish()
    }

    func resolveSearch(_ request: IntelligenceSearchRequest, debounce: Duration = .milliseconds(450),
                       interpret: (String, IntelligenceSearchContext) async throws -> String = { try await PRIntelligenceService.shared.suggestFilter($0, context: $1) }) async {
        guard request == snapshot.searchRequest else { return }
        let revision = UUID()
        searchRevision = revision
        searchMessage = nil
        understood = false
        guard request.needsInterpretation else {
            appliedQuery = request.text; isSearching = false; completedRequest = nil
            publish()
            return
        }
        if completedRequest == request { understood = true; isSearching = false; publish(); return }
        isSearching = true
        publish()
        do {
            try await Task.sleep(for: debounce)
            try Task.checkCancellation()
            let filter = try await interpret(request.text, request.context)
            try Task.checkCancellation()
            guard searchRevision == revision, snapshot.searchRequest == request else { return }
            appliedQuery = filter; completedRequest = request; understood = true
        } catch {
            guard !Task.isCancelled, searchRevision == revision, snapshot.searchRequest == request else { return }
            appliedQuery = request.text; completedRequest = nil
            if let failure = error as? PRIntelligenceService.Failure {
                switch failure {
                case .unsupported: searchMessage = "Couldn’t understand this search. Try phrasing it differently."
                default: searchMessage = failure.localizedDescription
                }
            } else { searchMessage = "Couldn’t finish this search. Try again in a moment." }
        }
        isSearching = false
        publish()
    }

    private func publish() {
        let request = IntelligenceSearchRequest(text: query, enabled: input?.intelligentSearch ?? false,
            context: context, hasLiteralMatches: items.contains { $0.matches(query) })
        if request != snapshot.searchRequest {
            searchRevision = UUID()
            understood = completedRequest == request
            isSearching = request.needsInterpretation && !understood
            searchMessage = nil
        }
        let effective = request.needsInterpretation ? appliedQuery : query
        let brush = effective.split(whereSeparator: \.isWhitespace).compactMap { TimelinePolicy.idleRange(String($0)) }.first
        let key = PresentationKey(tab: tab, query: effective, sortOrder: input?.sortOrder ?? .updatedNewest, collapsed: collapsed)
        let presentation: TimelinePresentation
        if presentationKey == key { presentation = snapshot.presentation }
        else {
            presentation = TimelinePresentation(items: items, tab: tab, query: effective,
                sortOrder: key.sortOrder, brush: brush, collapsed: collapsed)
            presentationKey = key
        }
        if let current = selection, presentation.visibleIDs.contains(current) || presentation.navigationIDs.contains(current) {
            // Keep the selected filtered stack companion, including its detail.
        } else { selection = presentation.navigationIDs.first }
        snapshot = TimelineScreenSnapshot(items: items, tabItems: items.filter { tab == .all || (tab == .mine ? $0.isMine : !$0.isMine) },
            presentation: presentation, brief: brief, searchRequest: request, tab: tab, query: query, effectiveQuery: effective,
            brush: brush, zone: Freshness.allCases.first { zoneRange($0) == brush }, selection: selection,
            isSearching: request.needsInterpretation && isSearching, understood: request.needsInterpretation && understood,
            searchMessage: request.needsInterpretation ? searchMessage : nil)
    }
}
