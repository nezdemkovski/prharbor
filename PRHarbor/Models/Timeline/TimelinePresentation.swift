import Foundation

/// One immutable presentation per data/filter change. View updates never regroup PRs.
nonisolated struct TimelinePresentation: Equatable, Sendable {
    enum Row: Identifiable, Equatable, Sendable {
        case repository(name: String, items: [TimelineItem], collapsed: Bool)
        case pull(TimelineItem)
        case stack(PullDisplayGroup, items: [TimelineItem])
        func normalizedSelection(_ selection: String?) -> String? {
            guard let selection else { return nil }
            switch self {
            case .repository: return nil
            case .pull(let item): return item.id == selection ? selection : nil
            case .stack(_, let items): return items.contains { $0.id == selection } ? selection : nil
            }
        }
        var id: String {
            switch self {
            case .repository(let name, _, _): "repo:" + name
            case .pull(let item): "pull:" + item.id
            case .stack(let group, _): "stack:" + group.id
            }
        }
    }
    private(set) var rows: [Row] = []
    private(set) var visibleIDs: Set<String> = []
    private(set) var navigationIDs: [String] = []
    private(set) var itemsByID: [String: TimelineItem] = [:]
    private(set) var contentHeight: CGFloat = TimelineRowGeometry.documentBottomPadding
    private(set) var scrollTargets: [String: String] = [:]
    private(set) var rowRanges: [String: Range<CGFloat>] = [:]
    private(set) var showOwner = false

    init(items: [TimelineItem] = [], tab: TimelineTab = .all, query: String = "",
         sortOrder: SortOrder = .updatedNewest, brush: ClosedRange<Double>? = nil, collapsed: [String] = []) {
        itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        showOwner = Set(items.map { $0.pull.repository.nameWithOwner.split(separator: "/").first }).count > 1
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let visible = items.filter { item in
            (tab == .all || (tab == .mine ? item.isMine : !item.isMine))
                && item.matches(terms: terms) && (brush.map { item.hasKnownQuietPeriod && $0.contains(item.quietDays) } ?? true)
        }.sorted { a, b in
            let first: Date, second: Date
            switch sortOrder {
            case .updatedNewest, .updatedOldest: first = a.pull.updatedAt; second = b.pull.updatedAt
            case .createdNewest, .createdOldest: first = a.pull.createdAt; second = b.pull.createdAt
            }
            if first == second { return a.id < b.id }
            return sortOrder == .updatedNewest || sortOrder == .createdNewest ? first > second : first < second
        }
        visibleIDs = Set(visible.map(\.id))
        let allByRepo = Dictionary(grouping: items) { $0.pull.repository.nameWithOwner }
        let grouped = Dictionary(grouping: visible) { $0.isBot ? "Bots" : $0.pull.repository.nameWithOwner }
        let names = grouped.keys.sorted { a, b in
            if a == "Bots" { return false }; if b == "Bots" { return true }; return a < b
        }
        let collapsed = Set(collapsed)
        for name in names {
            let matched = grouped[name] ?? []
            let isCollapsed = name == "Bots" ? !collapsed.contains(name) : collapsed.contains(name)
            rows.append(.repository(name: name, items: matched, collapsed: isCollapsed))
            guard !isCollapsed else { continue }
            // Keep companion layers visible when one layer of a stack matches the filter.
            let stackIDs = Set(matched.compactMap { $0.pull.stack?.id })
            let known = Set(matched.map(\.id))
            let companions = (allByRepo[name] ?? []).filter {
                !known.contains($0.id) && $0.pull.stack.map { stackIDs.contains($0.id) } == true
            }
            for group in groupPullsForDisplay((matched + companions).map { Edge(node: $0.pull) }) {
                let unitItems = group.edges.compactMap { itemsByID[$0.node.url.absoluteString] }
                if group.stack != nil, name != "Bots" {
                    rows.append(.stack(group, items: unitItems))
                    let hidden = collapsed.contains("stack:" + group.id)
                    if !hidden {
                        navigationIDs += unitItems.map(\.id)
                        for item in unitItems { scrollTargets[item.id] = "stack:" + group.id }
                    }
                } else {
                    rows += unitItems.map(Row.pull)
                    navigationIDs += unitItems.map(\.id)
                    for item in unitItems { scrollTargets[item.id] = "pull:" + item.id }
                }
            }
        }
        var y: CGFloat = 0
        for row in rows {
            let height: CGFloat
            switch row {
            case .repository: height = TimelineRowGeometry.repositoryHeight
            case .pull(let item):
                height = TimelineRowGeometry.pullHeight
                rowRanges[item.id] = y..<(y + height)
            case .stack(let group, let layers):
                let hidden = collapsed.contains("stack:" + group.id)
                height = TimelineRowGeometry.stackHeight(layers: layers.count, collapsed: hidden)
                if !hidden {
                    for (index, item) in layers.enumerated() {
                        rowRanges[item.id] = TimelineRowGeometry.layerRange(index: index, origin: y)
                    }
                }
            }
            rowRanges[row.id] = y..<(y + height)
            y += height
        }
        contentHeight = y + TimelineRowGeometry.documentBottomPadding
    }
}
