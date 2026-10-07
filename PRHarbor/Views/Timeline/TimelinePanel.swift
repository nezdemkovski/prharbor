import SwiftUI
import Defaults

struct TimelinePanel: View {
    @ObservedObject var store: PullRequestStore
    let now: Date
    let onSettings: () -> Void
    let onAbout: () -> Void
    let onQuit: () -> Void
    var previewItems: [TimelineItem]? = nil
    var scrollRendering: TimelineScrollRendering = .automatic
    private var rendering: TimelineScrollRendering {
        scrollRendering == .automatic ? .native : scrollRendering
    }
    @Default(.timelineRange) private var range
    @Default(.detailHistory) private var history
    @Default(.freshnessThresholds) private var thresholds
    @Default(.botAccounts) private var bots
    @Default(.ownCommentsCount) private var ownComments
    @Default(.githubUsername) private var username
    @Default(.showRequested) private var showRequested
    @Default(.showAssigned) private var showAssigned
    @Default(.showCreated) private var showCreated
    @Default(.sortOrder) private var sortOrder
    @Default(.snoozedPulls) private var snoozed
    @Default(.collapsedRepos) private var collapsed
    @Default(.intelligentSearch) private var intelligentSearch
    @Default(.intelligentMorningBrief) private var intelligentMorningBrief
    @State private var briefExpanded = false
    @StateObject private var screen = TimelineScreenController()
    @State private var interaction = TimelineInteraction()
    @FocusState private var searching: Bool
    @FocusState private var navigating: Bool
    @Environment(\.openURL) private var openURL
    private var scale: TimelineScale { TimelineScale(days: [14, 30, 90, 182].contains(range) ? range : 182) }
    private var screenInput: TimelineScreenInput {
        TimelineScreenInput(data: store.timelineInput(now: now, thresholds: thresholds, bots: bots,
            ownComments: ownComments, snoozed: snoozed, includeAssigned: showAssigned,
            includeCreated: showCreated, includeRequested: showRequested, username: username),
            previewItems: previewItems, sortOrder: sortOrder, collapsed: collapsed, intelligentSearch: intelligentSearch)
    }
    private var snapshot: TimelineScreenSnapshot { screen.snapshot }
    private var items: [TimelineItem] { snapshot.items }
    private var presentation: TimelinePresentation { snapshot.presentation }
    private var selected: TimelineItem? { snapshot.selected }
    private var selection: String? { snapshot.selection }
    private var brush: ClosedRange<Double>? { snapshot.brush }
    private var query: String { snapshot.query }
    private var briefSnapshot: MorningBriefSnapshot { snapshot.brief }
    private var queryBinding: Binding<String> { Binding(get: { snapshot.query }, set: screen.setQuery) }
    private var tabBinding: Binding<TimelineTab> { Binding(get: { snapshot.tab }, set: screen.setTab) }
    private var zoneBinding: Binding<Freshness?> { Binding(get: { snapshot.zone }, set: screen.setZone) }
    private var rowAreaHeight: CGFloat {
        presentation.visibleIDs.isEmpty ? 80 : min(max(100, 456 - briefHeight), presentation.contentHeight)
    }
    private var panelHeight: CGFloat {
        // Fixed chrome from timeline.html; the scroll region shrinks with filtered content.
        194 + rowAreaHeight + (selected == nil ? 0 : (history ? 127 : 96)) + (store.error == nil ? 0 : 36) + briefHeight
    }
    private var briefHeight: CGFloat {
        guard intelligentMorningBrief else { return 0 }
        return 44 + (briefExpanded ? (briefSnapshot.entries.isEmpty ? 52 : CGFloat(briefSnapshot.entries.count * 74 + 44)) : 0)
    }
    var body: some View {
        let request = snapshot.searchRequest
        VStack(spacing: 0) {
            TimelineSearchBar(query: queryBinding, focus: $searching, onNavigate: { searching = false; navigating = true; move(1) },
                              isUnderstanding: request.needsInterpretation && snapshot.isSearching,
                              understood: request.needsInterpretation && snapshot.understood,
                              searchMessage: request.needsInterpretation ? snapshot.searchMessage : nil, naturalLanguageEnabled: intelligentSearch)
            TimelineHeading(items: items, now: now, tab: tabBinding, range: $range, sortOrder: $sortOrder, store: store, isPreview: previewItems != nil, onSettings: onSettings, onAbout: onAbout, onQuit: onQuit)
            TimelineSummary(items: snapshot.tabItems, zone: zoneBinding)
                .padding(.horizontal, 18).padding(.top, 2).padding(.bottom, 12)
            if intelligentMorningBrief {
                TimelineMorningBrief(snapshot: briefSnapshot, expanded: $briefExpanded, select: select,
                                     emptyMessage: store.isLoading && items.isEmpty ? "Waiting for pull requests…" : store.error != nil && items.isEmpty ? "Refresh pull requests to prepare an overview." : "All clear. No pull requests need attention right now.")
                    .padding(.horizontal, 18).padding(.bottom, 8)
            }
            if let error = store.error {
                HStack {
                    SwiftUI.Label(error, systemImage: "exclamationmark.triangle").lineLimit(2)
                    Spacer(); Button("Retry") { store.refresh() }
                }.font(.caption).foregroundStyle(Theme.failure).padding(.horizontal, 18).padding(.bottom, 8)
            }
            TimelineInteractiveAxis(scale: scale, now: now, interaction: interaction, brush: brush, clearBrush: { writeIdle(nil) }).padding(.horizontal, 18)
            rows.frame(height: rowAreaHeight)
            if let selected {
                TimelineDetailView(item: selected, now: now, store: store, select: select, availableURLs: Set(presentation.itemsByID.keys))
                    .id(selected.id)
                    .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 18)
            }
        }
        .frame(width: TimelineMetrics.panelWidth, height: panelHeight, alignment: .top)
        .background(TimelineStyle.panel)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(TimelineStyle.line))
        .foregroundStyle(TimelineStyle.text)
        .tint(TimelineStyle.accent)
        .monospacedDigit()
        .focusable().focused($navigating).focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat], action: handleNavigation)
        .onChange(of: screenInput, initial: true) { _, value in screen.update(value) }
        .onChange(of: intelligentMorningBrief) { _, enabled in if !enabled { briefExpanded = false } }
        .task(id: request) { await screen.resolveSearch(request) }
    }
    private var rows: some View {
        Group {
            if rendering == .native, !presentation.visibleIDs.isEmpty {
                let rowsByID = Dictionary(uniqueKeysWithValues: presentation.rows.map { ($0.id, $0) })
                TimelineNativeScrollView(height: presentation.contentHeight, rowIDs: presentation.rows.map(\.id),
                    ranges: presentation.rowRanges, selection: selection, interaction: interaction,
                    content: { id in rowDocument(row: rowsByID[id]).id(id) },
                    placeholder: { id in placeholder(for: rowsByID[id]) },
                    activate: { id in activate(rowsByID[id]) })
            } else {
                swiftUIScrollView
            }
        }
        .background(alignment: .trailing) {
            if !presentation.visibleIDs.isEmpty {
                TimelineInteractiveGrid(scale: scale, now: now, interaction: interaction, brush: brush)
                    .frame(width: TimelineMetrics.trackWidth).padding(.trailing, TimelineMetrics.inset)
            }
        }
        .onChange(of: scale.days, initial: true) { _, _ in interaction.scale = scale }
    }
    private func rowDocument(row: TimelinePresentation.Row?) -> some View {
        Group { if let row { rowView(row) } }
            .focusable().focusEffectDisabled()
            .onKeyPress(phases: [.down, .repeat], action: handleNavigation)
            .padding(.horizontal, 18)
            .foregroundStyle(TimelineStyle.text).tint(TimelineStyle.accent).monospacedDigit()
            .onContinuousHover { phase in
                guard !interaction.isScrolling else { return }
                switch phase {
                case .active(let point): interaction.hover(at: point.x)
                case .ended: interaction.cursorAge = nil
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { value in
                interaction.drag(from: value.startLocation.x, to: value.location.x, scale: scale)
            }.onEnded { _ in
                if interaction.brushing { writeIdle(interaction.dragging) }
                interaction.endDrag()
            })
    }
    private var swiftUIScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if store.isLoading && items.isEmpty {
                    ProgressView("Fetching pull requests…").frame(maxWidth: .infinity).padding(.top, 20)
                } else if presentation.visibleIDs.isEmpty {
                    Text(emptyMessage)
                        .font(.system(size: 13)).foregroundStyle(TimelineStyle.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                } else {
                    Group {
                        if rendering == .eager { VStack(spacing: 0) { rowContent } }
                        else { LazyVStack(spacing: 0) { rowContent } }
                    }
                    .padding(.bottom, TimelineRowGeometry.documentBottomPadding).padding(.horizontal, 18)
                    .onContinuousHover { phase in
                        guard !interaction.isScrolling else { return }
                        switch phase {
                        case .active(let point): interaction.hover(at: point.x)
                        case .ended: interaction.cursorAge = nil
                        }
                    }
                    .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { value in
                        interaction.drag(from: value.startLocation.x, to: value.location.x, scale: scale)
                    }.onEnded { _ in
                        if interaction.brushing { writeIdle(interaction.dragging) }
                        interaction.endDrag()
                    })
                }
            }
            .scrollIndicators(.automatic)
            .onScrollPhaseChange { _, phase in
                interaction.isScrolling = phase != .idle
                if interaction.isScrolling { interaction.cursorAge = nil }
            }
            .onChange(of: selection) { _, value in if let value { proxy.scrollTo(presentation.scrollTargets[value] ?? value, anchor: nil) } }
        }
    }
    private var rowContent: some View {
        ForEach(presentation.rows) { row in rowView(row) }
    }
    private func rowView(_ row: TimelinePresentation.Row) -> some View {
        TimelinePresentedRow(row: row, scale: scale, now: now, selection: row.normalizedSelection(selection),
            showOwner: presentation.showOwner, stackCollapsed: stackCollapsed(row),
            height: presentation.rowRanges[row.id].map { $0.upperBound - $0.lowerBound },
            select: select, toggleRepo: toggleRepo).equatable()
    }

    private func stackCollapsed(_ row: TimelinePresentation.Row) -> Bool {
        if case .stack(_, let items) = row { return !items.contains { presentation.rowRanges[$0.id] != nil } }
        return false
    }
    private func placeholder(for row: TimelinePresentation.Row?) -> TimelineRowPlaceholder {
        switch row {
        case .repository(let name, let items, _):
            TimelineRowPlaceholder(title: name + " · \(items.count)", subtitle: "", isRepository: true)
        case .pull(let item):
            TimelineRowPlaceholder(title: item.title, subtitle: "#\(item.pull.number) · \(item.pull.author?.login ?? "ghost")")
        case .stack(_, let items):
            TimelineRowPlaceholder(title: items.first?.title ?? "Stack", subtitle: "\(items.count) layers")
        case nil: TimelineRowPlaceholder(title: "", subtitle: "")
        }
    }
    private func activate(_ row: TimelinePresentation.Row?) {
        switch row {
        case .repository(let name, _, _): toggleRepo(name)
        case .pull(let item): select(item.id)
        case .stack(_, let items): if let item = items.first { select(item.id) }
        case nil: break
        }
    }

    private func handleNavigation(_ press: KeyPress) -> KeyPress.Result {
        guard !searching else { return .ignored }
        switch press.key {
        case .downArrow: move(1)
        case .upArrow: move(-1)
        case .return: primary()
        case .escape: screen.clearQuery()
        default:
            guard press.modifiers.intersection([.command, .control, .option]).isEmpty else { return .ignored }
            let character = press.characters.isEmpty ? String(press.key.character) : press.characters
            switch character.lowercased() {
            case "/": searching = true
            case "j": move(1)
            case "k": move(-1)
            case "o": if let selected { openURL(selected.pull.url) }
            case "s": toggleSnooze()
            default: return .ignored
            }
        }
        return .handled
    }

    private var emptyMessage: String {
        let request = snapshot.searchRequest
        if request.needsInterpretation, snapshot.isSearching { return "Searching…" }
        if request.needsInterpretation, let message = snapshot.searchMessage { return message }
        return query.isEmpty && snapshot.zone == nil && brush == nil ? "All clear. No open pull requests." : "Nothing matches. Nice and clean."
    }
    private func writeIdle(_ value: ClosedRange<Double>?) { screen.writeIdle(value) }
    private func select(_ id: String) {
        guard let value = screen.select(id) else { return }
        collapsed = value
        searching = false; navigating = true
    }
    private func toggleRepo(_ name: String) { collapsed = screen.toggleCollapsed(name) }
    private func move(_ delta: Int) { screen.move(delta) }
    private func toggleSnooze() {
        guard let selected, selected.pull.stack == nil || selected.pull.stack?.size == 1 else { return }
        if selected.snoozedUntil == nil {
            snoozed[selected.id] = now.addingTimeInterval(3 * 86_400).timeIntervalSince1970
            Defaults[.snoozeActivity][selected.id] = now.timeIntervalSince1970
        } else {
            snoozed.removeValue(forKey: selected.id)
            Defaults[.snoozeActivity].removeValue(forKey: selected.id)
        }
    }
    private func primary() {
        guard let selected else { return }
        if selected.isBlocked, let base = selected.blockedBy {
            if items.contains(where: { $0.id == base.url.absoluteString }) { select(base.url.absoluteString) } else { openURL(base.url) }
        } else { openURL(selected.pull.url) }
    }
}

/// Content equality excludes action closures, which access the panel's live
/// State/Defaults storage. Scrolling retains overlapping row render trees.
struct TimelinePresentedRow: View, Equatable {
    let row: TimelinePresentation.Row
    let scale: TimelineScale
    let now: Date
    let selection: String?
    let showOwner: Bool
    let stackCollapsed: Bool
    let height: CGFloat?
    let select: (String) -> Void
    let toggleRepo: (String) -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.row == rhs.row && lhs.scale == rhs.scale && lhs.now == rhs.now
            && lhs.selection == rhs.selection && lhs.showOwner == rhs.showOwner
            && lhs.stackCollapsed == rhs.stackCollapsed && lhs.height == rhs.height
    }
    var body: some View {
        Group {
            switch row {
            case .repository(let name, let items, let collapsed):
                TimelineRepositoryHeader(name: name, items: items, scale: scale,
                    collapsed: collapsed, showOwner: showOwner) { toggleRepo(name) }
            case .pull(let item):
                TimelineRow(item: item, scale: scale, now: now, selected: selection == item.id) { select(item.id) }
            case .stack(let group, let items):
                TimelineStackRows(group: group, items: items, scale: scale, now: now, selection: selection,
                    isCollapsed: stackCollapsed,
                    select: select, toggle: { toggleRepo("stack:" + group.id) })
            }
        }.frame(height: height, alignment: .top)
    }
}
