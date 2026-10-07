import Foundation
import Defaults
import SwiftUI
import Security
import ImageIO
import Testing
@testable import PRHarbor

@Suite("Timeline presentation")
struct TimelinePresentationTests {
    @Test @MainActor func pointerCoordinatesRespectThePaddedTrackBounds() {
        let interaction = TimelineInteraction()
        let origin = TimelineMetrics.inset + TimelineMetrics.labelWidth
        let right = TimelineMetrics.panelWidth - TimelineMetrics.inset
        interaction.hover(at: origin - 1)
        #expect(interaction.cursorAge == nil)
        interaction.hover(at: origin)
        #expect(abs((interaction.cursorAge ?? 0) - 182) < 0.000001)
        interaction.hover(at: right)
        #expect(interaction.cursorAge == 0)
        interaction.hover(at: right + 1)
        #expect(interaction.cursorAge == nil)
        interaction.drag(from: origin - 1, to: right, scale: interaction.scale)
        #expect(!interaction.brushing)
        interaction.drag(from: origin, to: right, scale: interaction.scale)
        #expect(interaction.dragging?.lowerBound == 0)
        #expect(interaction.dragging?.upperBound == .infinity)
        interaction.endDrag()
        #expect(!interaction.brushing && interaction.dragging == nil)
    }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    @Test func nativeRowRangesMatchLayerHeightsAndCollapsedContent() {
        let stack = PullRequestStack(id: "range-stack", number: 1, baseRefName: "main", size: 2)
        let base = item(1, stack: stack, position: 1)
        let tip = item(2, stack: stack, position: 2)
        let snapshot = TimelinePresentation(items: [base, tip, item(3)])
        let first = snapshot.rowRanges[base.id]!
        let second = snapshot.rowRanges[tip.id]!
        #expect(first.upperBound - first.lowerBound == 44)
        #expect(first.lowerBound - second.lowerBound == 44) // Higher stack layers are above the base.
        #expect(snapshot.rowRanges.values.map(\.upperBound).max()! + 4 == snapshot.contentHeight)
        let collapsed = TimelinePresentation(items: [base, tip], collapsed: ["stack:range-stack"])
        #expect(collapsed.rowRanges[base.id] == nil)
        #expect(collapsed.rowRanges["stack:range-stack"]?.upperBound == 110)
        #expect(collapsed.contentHeight == 114)
    }

    private func item(_ number: Int, repo: String = "example/repo", author: String = "octocat", stack: PullRequestStack? = nil,
                      position: Int? = nil, days: Double = 10) -> TimelineItem {
        let pull = Pull(url: URL(string: "https://github.com/\(repo)/pull/\(number)")!,
                        updatedAt: now.addingTimeInterval(-days * 86_400), createdAt: now.addingTimeInterval(-days * 86_400),
                        title: "HQ-\(number): Change \(number)", number: number, reviews: Review(totalCount: 0, edges: []),
                        author: User(login: author), repository: Repository(name: "repo", nameWithOwner: repo),
                        labels: Nodes(nodes: []), headRefName: "feature/\(number)", isDraft: false, isReadByViewer: true,
                        stack: stack, stackEntry: position.map { PullRequestStackPosition(position: $0) })
        return TimelineItem(pull: pull, username: "octocat", now: now, thresholds: [2, 7, 21], bots: ["*[bot]"],
                            ownComments: true, snoozedUntil: nil)
    }
    @Test func filteredStackRetainsCompanionsAndDependencyOrder() {
        let stack = PullRequestStack(id: "stack-one", number: 1, baseRefName: "main", size: 2)
        let base = item(10, stack: stack, position: 1), tip = item(11, stack: stack, position: 2)
        let snapshot = TimelinePresentation(items: [base, tip, item(12)], query: "#10")
        #expect(snapshot.visibleIDs == [base.id])
        #expect(snapshot.navigationIDs == [tip.id, base.id])
        #expect(snapshot.scrollTargets[tip.id] == "stack:stack-one")
        let hidden = TimelinePresentation(items: [base, tip], query: "#10", collapsed: ["stack:stack-one"])
        #expect(hidden.navigationIDs.isEmpty)
        #expect(hidden.rows.count == 2)
    }
    @Test func repositoryAndBotCollapseRespectKeyboardNavigation() {
        let regular = item(1), bot = item(2, author: "checks[bot]")
        let snapshot = TimelinePresentation(items: [bot, regular])
        #expect(snapshot.navigationIDs == [regular.id])
        #expect(snapshot.rows.count == 3)
        let expanded = TimelinePresentation(items: [bot, regular], collapsed: ["Bots", "example/repo"])
        #expect(expanded.navigationIDs == [bot.id])
        #expect(Set(expanded.rows.map(\.id)).count == expanded.rows.count)
        #expect(expanded.scrollTargets[bot.id] == "pull:" + bot.id)
    }
    @Test func tabBrushAndSortPreserveMatchingRowsAndStableTies() {
        let young = item(1, days: 1), old = item(2, days: 30), review = item(3, author: "reviewer", days: 30)
        let mine = TimelinePresentation(items: [review, young, old], tab: .mine, brush: 7...40)
        #expect(mine.navigationIDs == [old.id])
        let first = TimelinePresentation(items: [review, old], sortOrder: .createdNewest)
        let second = TimelinePresentation(items: [old, review], sortOrder: .createdNewest)
        #expect(first.navigationIDs == second.navigationIDs)
        #expect(TimelinePresentation(items: [old], query: "absent").rows.isEmpty)
    }
    @Test @MainActor func rowUpdatesForCIOrReviewChangesWithoutANewUpdatedAt() {
        var original = item(1).pull
        original.commits = CommitsNodes(nodes: [Commit(commit: CheckSuites(
            statusCheckRollup: StatusCheckRollup(state: "PENDING")))])
        func rendered(_ pull: Pull) -> TimelinePresentedRow {
            let value = TimelineItem(pull: pull, username: "octocat", now: now,
                thresholds: [2, 7, 21], bots: ["*[bot]"], ownComments: true, snoozedUntil: nil)
            return TimelinePresentedRow(row: .pull(value), scale: TimelineScale(days: 182), now: now,
                selection: nil, showOwner: false, stackCollapsed: false, height: 50,
                select: { _ in }, toggleRepo: { _ in })
        }
        var reviewed = original
        reviewed.reviewDecision = "APPROVED"
        #expect(original.updatedAt == reviewed.updatedAt)
        #expect(rendered(original) != rendered(reviewed))
        var checked = original
        checked.commits?.nodes[0].commit.statusCheckRollup?.state = "SUCCESS"
        #expect(original.updatedAt == checked.updatedAt)
        #expect(rendered(original) != rendered(checked))
        let pending = CICheck(name: "build", status: "PENDING", url: nil, index: 0)
        let success = CICheck(name: "build", status: "SUCCESS", url: nil, index: 0)
        #expect(pending.id == success.id)
    }
    @Test func compiledBotPatternsHandleUnicodeAndLiteralRegexSymbols() {
        let matcher = TimelineBotMatcher(patterns: ["*[bot]", "build.agent", "бот*"])
        #expect(matcher.matches("checks[bot]"))
        #expect(matcher.matches("BUILD.AGENT"))
        #expect(matcher.matches("бот-тест"))
        #expect(!matcher.matches("buildXagent"))
        #expect(!matcher.matches(nil))
    }
}
