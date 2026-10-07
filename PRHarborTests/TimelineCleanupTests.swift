import AppKit
import SwiftUI
import Testing
@testable import PRHarbor

struct TimelineCleanupTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ number: Int, author: String = "yuri", days: Double = 10,
                      stack: PullRequestStack? = nil, position: Int? = nil) -> TimelineItem {
        let pull = Pull(url: URL(string: "https://github.com/example/repo/pull/\(number)")!,
            updatedAt: now.addingTimeInterval(-days * 86_400), createdAt: now.addingTimeInterval(-days * 86_400),
            title: "Change \(number)", number: number, reviews: Review(totalCount: 0, edges: []), author: User(login: author),
            repository: Repository(name: "repo", nameWithOwner: "example/repo"), labels: Nodes(nodes: []),
            headRefName: "feature/\(number)", isDraft: false, isReadByViewer: true,
            stack: stack, stackEntry: position.map { PullRequestStackPosition(position: $0) })
        return TimelineItem(pull: pull, username: "yuri", now: now, thresholds: [2, 7, 21], bots: [],
            ownComments: true, snoozedUntil: nil, reviewRequested: author != "yuri")
    }
    private func input(_ items: [TimelineItem], collapsed: [String] = [], intelligentSearch: Bool = false) -> TimelineScreenInput {
        TimelineScreenInput(data: TimelineInput(edges: [], reviewURLs: [], username: "yuri", now: now,
            thresholds: [2, 7, 21], bots: [], ownComments: true, snoozed: [:]), previewItems: items,
            sortOrder: .updatedNewest, collapsed: collapsed, intelligentSearch: intelligentSearch)
    }

    @Test @MainActor func dataTabFilterAndSelectionAlwaysDescribeTheSameSnapshot() {
        let controller = TimelineScreenController()
        let mine = item(1), reviewer = item(2, author: "reviewer")
        controller.update(input([mine, reviewer]))
        controller.setTab(.reviewing)
        #expect(controller.snapshot.tabItems == [reviewer])
        #expect(controller.snapshot.presentation.visibleIDs == [reviewer.id])
        #expect(controller.snapshot.selected == reviewer)
        let replacement = item(3, author: "reviewer")
        controller.update(input([mine, replacement]))
        #expect(controller.snapshot.items == [mine, replacement])
        #expect(controller.snapshot.tabItems == [replacement])
        #expect(controller.snapshot.selected == replacement)
        #expect(controller.snapshot.presentation.itemsByID[reviewer.id] == nil)
        controller.setQuery("#1")
        #expect(controller.snapshot.selected == nil)
        #expect(controller.snapshot.presentation.navigationIDs.isEmpty)
        controller.setTab(.mine)
        #expect(controller.snapshot.selected == mine)
    }

    @Test @MainActor func brushAndZoneAreDerivedTogetherAndClearPreservesOtherTerms() {
        let controller = TimelineScreenController()
        controller.update(input([item(1, days: 1), item(2, days: 10)]))
        controller.setQuery("mine")
        controller.setZone(.stale)
        #expect(controller.snapshot.query == "mine idle:7d-21d")
        #expect(controller.snapshot.brush == 7...21)
        #expect(controller.snapshot.zone == .stale)
        #expect(controller.snapshot.selected?.pull.number == 2)
        controller.writeIdle(nil)
        #expect(controller.snapshot.query == "mine")
        #expect(controller.snapshot.brush == nil && controller.snapshot.zone == nil)
    }

    @Test @MainActor func selectingAHiddenBriefEntryRevealsItsRepositoryAndStackTogether() {
        let controller = TimelineScreenController()
        let stack = PullRequestStack(id: "selected-stack", number: 1, baseRefName: "main", size: 2)
        let base = item(1, stack: stack, position: 1), tip = item(2, stack: stack, position: 2)
        controller.update(input([base, tip], collapsed: ["example/repo", "stack:selected-stack"]))
        controller.setTab(.reviewing)
        controller.setQuery("absent")
        let collapsed = controller.select(base.id)
        #expect(collapsed == [])
        #expect(controller.snapshot.tab == .all && controller.snapshot.query.isEmpty)
        #expect(controller.snapshot.presentation.navigationIDs == [tip.id, base.id])
        #expect(controller.snapshot.selection == base.id)
        #expect(controller.snapshot.presentation.rowRanges[base.id] != nil)
    }

    @Test @MainActor func selectionChangesDoNotInvalidateUnrelatedLiveRows() {
        let first = item(1), second = item(2), unaffected = item(3)
        let rows: [TimelinePresentation.Row] = [.repository(name: "example/repo", items: [first, second, unaffected], collapsed: false),
            .pull(first), .pull(second), .pull(unaffected)]
        func rendered(_ row: TimelinePresentation.Row, selection: String) -> TimelinePresentedRow {
            TimelinePresentedRow(row: row, scale: TimelineScale(days: 182), now: now,
                selection: row.normalizedSelection(selection), showOwner: false, stackCollapsed: false,
                height: nil, select: { _ in }, toggleRepo: { _ in })
        }
        #expect(rendered(rows[0], selection: first.id) == rendered(rows[0], selection: second.id))
        #expect(rendered(rows[3], selection: first.id) == rendered(rows[3], selection: second.id))
        #expect(rendered(rows[1], selection: first.id) != rendered(rows[1], selection: second.id))
        #expect(rendered(rows[2], selection: first.id) != rendered(rows[2], selection: second.id))
    }

    @Test @MainActor func movingSelectionDuringNaturalSearchKeepsThePendingResponseValid() async {
        let controller = TimelineScreenController()
        controller.update(input([item(1), item(2)], intelligentSearch: true))
        controller.setQuery("My PRs older than two weeks")
        let request = controller.snapshot.searchRequest
        var completion: CheckedContinuation<String, Never>?
        let task = Task {
            await controller.resolveSearch(request, debounce: .zero) { _, _ in
                await withCheckedContinuation { completion = $0 }
            }
        }
        while completion == nil { await Task.yield() }
        let presentation = controller.snapshot.presentation
        controller.move(1)
        #expect(controller.snapshot.presentation == presentation)
        #expect(controller.snapshot.isSearching)
        completion?.resume(returning: "mine stale")
        await task.value
        #expect(controller.snapshot.effectiveQuery == "mine stale")
        #expect(controller.snapshot.understood && !controller.snapshot.isSearching)
    }

    @Test(arguments: [2, 3, 10]) @MainActor func collapsedStackGeometryContainsRenderedBarsAndKeepsFollowingRowsSeparate(_ count: Int) throws {
        let stack = PullRequestStack(id: "geometry-stack", number: 1, baseRefName: "main", size: count)
        let layers = (1...count).map { item($0, stack: stack, position: $0) }
        let following = item(100)
        let presentation = TimelinePresentation(items: layers + [following], collapsed: ["stack:geometry-stack"])
        let range = try #require(presentation.rowRanges["stack:geometry-stack"])
        let expected = max(70, CGFloat(count * 4 + (count - 1) * 2 + 16 + 32 + 8))
        #expect(range.upperBound - range.lowerBound == expected)
        #expect(layers.allSatisfy { presentation.rowRanges[$0.id] == nil })
        let pullRange = try #require(presentation.rowRanges["pull:" + following.id])
        #expect(pullRange.lowerBound == range.upperBound || pullRange.upperBound == range.lowerBound)
        let group = try #require(groupPullsForDisplay(layers.map { Edge(node: $0.pull) }).first)
        let view = TimelineStackRows(group: group, items: layers, scale: TimelineScale(days: 182), now: now,
            selection: nil, isCollapsed: true, select: { _ in }, toggle: {})
        let host = NSHostingView(rootView: view.fixedSize(horizontal: false, vertical: true))
        host.frame = NSRect(x: 0, y: 0, width: TimelineMetrics.panelWidth - 36, height: expected)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.height <= expected + 0.5)
        if count >= 3 { #expect(abs(host.fittingSize.height - expected) < 0.5) }
    }
}
