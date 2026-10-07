import Foundation
import Defaults
import SwiftUI
import Security
import ImageIO
import Testing
@testable import PRHarbor

struct IntelligencePolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func item(number: Int, author: String = "yuri", quiet: Double = 12, draft: Bool = false, snoozed: Bool = false, requested: Bool = false, conflict: Bool = false) -> TimelineItem {
        let pull = Pull(url: URL(string: "https://github.com/example/repo/pull/\(number)")!,
                        updatedAt: now.addingTimeInterval(-quiet * 86_400), createdAt: now.addingTimeInterval(-30 * 86_400),
                        title: "A change \(number)", number: number, reviews: Review(totalCount: 0, edges: []), author: User(login: author),
                        repository: Repository(name: "repo", nameWithOwner: "example/repo"), labels: Nodes(nodes: []), headRefName: "feature", isDraft: draft,
                        isReadByViewer: true, mergeable: conflict ? "CONFLICTING" : "MERGEABLE")
        return TimelineItem(pull: pull, username: "yuri", now: now, thresholds: [2, 7, 21], bots: ["*[bot]"], ownComments: true,
                            snoozedUntil: snoozed ? now.addingTimeInterval(86_400) : nil, reviewRequested: requested)
    }
    @Test func generatedFiltersUseExistingParserAndKeepAgeSeparateFromQuietTime() throws {
        let value = item(number: 42, quiet: 1)
        let context = IntelligenceSearchContext(items: [value])
        let query = try #require(context.validatedQuery(["MINE", ">2w", "example/repo", "idle:0d-2d"]))
        #expect(value.matches(query))
        #expect(!value.matches(try #require(context.validatedQuery(["mine", "idle:14d+"]))))
        #expect(context.validatedQuery(["mine", "mine", "@yuri", "#42"]) == "mine @yuri #42")
        #expect(context.explicitRepositories(in: "My PRs in EXAMPLE/repo with conflicts") == ["example/repo"])
        #expect(context.explicitRepositories(in: "My PRs in example/repo-tools").isEmpty)
        #expect(context.validatedSuggestion(["mine", ">2w", "example/repo"], request: "My PRs older than two weeks") == "mine >2w")
        #expect(context.validatedSuggestion(["mine", " EXAMPLE/repo "], request: "My PRs") == "mine")
        #expect(context.validatedSuggestion(["mine", "conflict"], request: "My PRs in example/repo with conflicts") == "mine conflict example/repo")
    }
    @Test func rejectsInventedFiltersMalformedRangesAndSilentFreeText() {
        let context = IntelligenceSearchContext(items: [item(number: 42)])
        for tokens in [[], ["needs-review"], ["mine >2w"], ["repo:example/repo"], ["unknown/repo"], ["@unknown"], [">nan"], ["idle:-2d+"], ["#0"], ["not:draft"], Array(repeating: "mine", count: 9)] {
            #expect(context.validatedQuery(tokens) == nil)
        }
    }
    @Test func naturalLanguageExtendsExistingSearchWithoutInterceptingLiteralSearches() {
        let context = IntelligenceSearchContext(items: [item(number: 42)])
        #expect(context.shouldInterpret("My PRs older than two weeks", hasLiteralMatches: false))
        #expect(context.shouldInterpret("PRs quiet for at least seven days", hasLiteralMatches: false))
        #expect(context.shouldInterpret("draft PRs", hasLiteralMatches: false))
        for query in ["mine stale", "example/repo >2w", "#42", "feature/useful", "unmatched title"] {
            #expect(!context.shouldInterpret(query, hasLiteralMatches: false))
        }
        #expect(!context.shouldInterpret("A title with natural words", hasLiteralMatches: true))
    }
    @MainActor private func screenInput(enabled: Bool = true) -> TimelineScreenInput {
        TimelineScreenInput(data: TimelineInput(edges: [], reviewURLs: [], username: "yuri", now: now,
            thresholds: [2, 7, 21], bots: [], ownComments: true, snoozed: [:]),
            previewItems: [item(number: 42)], sortOrder: .updatedNewest, collapsed: [], intelligentSearch: enabled)
    }
    @Test @MainActor func naturalSearchKeepsEnteredTextAndAppliesInterpretationInternally() async {
        let controller = TimelineScreenController()
        controller.update(screenInput())
        controller.setQuery("My PRs older than two weeks")
        let request = controller.snapshot.searchRequest
        await controller.resolveSearch(request, debounce: .zero) { text, _ in
            #expect(text == request.text)
            return "mine >2w"
        }
        #expect(controller.snapshot.effectiveQuery == "mine >2w")
        #expect(controller.snapshot.query == "My PRs older than two weeks")
        #expect(controller.snapshot.understood)
        #expect(!controller.snapshot.isSearching)
        controller.update(screenInput(enabled: false))
        #expect(controller.snapshot.effectiveQuery == request.text)
        await controller.resolveSearch(controller.snapshot.searchRequest, debounce: .zero) { _, _ in
            Issue.record("Disabled search must not call the model")
            return ""
        }
        #expect(!controller.snapshot.understood)
    }
    @Test @MainActor func ordinarySearchDoesNotWaitForOrCallTheModel() async {
        let controller = TimelineScreenController()
        controller.update(screenInput())
        controller.setQuery("mine stale")
        #expect(controller.snapshot.effectiveQuery == "mine stale")
        await controller.resolveSearch(controller.snapshot.searchRequest) { _, _ in
            Issue.record("Native syntax must bypass generation"); return ""
        }
        #expect(!controller.snapshot.isSearching)
    }
    @Test @MainActor func clearedSearchCannotBeOverwrittenByALateModelResponse() async {
        let controller = TimelineScreenController()
        controller.update(screenInput())
        controller.setQuery("My PRs older than two weeks")
        let firstRequest = controller.snapshot.searchRequest
        var completion: CheckedContinuation<String, Never>?
        let first = Task {
            await controller.resolveSearch(firstRequest, debounce: .zero) { _, _ in
                await withCheckedContinuation { completion = $0 }
            }
        }
        while completion == nil { await Task.yield() }
        controller.clearQuery()
        await controller.resolveSearch(controller.snapshot.searchRequest, debounce: .zero)
        completion?.resume(returning: "mine >2w")
        await first.value
        #expect(controller.snapshot.query.isEmpty)
        #expect(controller.snapshot.effectiveQuery.isEmpty)
        #expect(!controller.snapshot.understood)
        #expect(!controller.snapshot.isSearching)
    }
    @Test func morningBriefExcludesBotsDraftsAndSnoozesAndKeepsCountsFactual() {
        let items = [item(number: 1, conflict: true), item(number: 2, author: "reviewer", requested: true), item(number: 3),
                     item(number: 4, author: "checks[bot]", requested: true), item(number: 5, draft: true), item(number: 6, snoozed: true),
                     item(number: 7, author: "assigned", requested: false)]
        let brief = MorningBriefSnapshot(items: items, now: now)
        #expect(brief.entries.map(\.number) == [1, 2, 3])
        #expect(brief.waitingForReview == 1)
        #expect(brief.quietOwned == 2)
        #expect(brief.entries[0].action == "Rebase")
        #expect(brief.entries[0].reason.contains("Merge conflict"))
        #expect(MorningBriefSnapshot(items: [], now: now).entries.isEmpty)
    }
    @Test func morningBriefUsesOneBasePerStackAndIgnoresListOrdering() {
        var base = item(number: 10, author: "reviewer", requested: true)
        var child = item(number: 11, author: "reviewer", requested: true)
        let stack = PullRequestStack(id: "stack", number: 1, baseRefName: "main", size: 2)
        var basePull = base.pull; basePull.stack = stack; basePull.stackEntry = PullRequestStackPosition(position: 1)
        var childPull = child.pull; childPull.stack = stack; childPull.stackEntry = PullRequestStackPosition(position: 2)
        base = TimelineItem(pull: basePull, username: "yuri", now: now, thresholds: [2, 7, 21], bots: [], ownComments: true, snoozedUntil: nil, reviewRequested: true)
        child = TimelineItem(pull: childPull, username: "yuri", now: now, thresholds: [2, 7, 21], bots: [], ownComments: true, snoozedUntil: nil, reviewRequested: true)
        let brief = MorningBriefSnapshot(items: [child, item(number: 12), base], now: now)
        #expect(brief.entries.map(\.number) == [10, 12])
        #expect(brief == MorningBriefSnapshot(items: [base, child, item(number: 12)], now: now))
    }
    @Test func briefCacheSnapshotChangesWithFactsAndDayInsteadOfEveryRefresh() {
        let value = item(number: 1)
        let brief = MorningBriefSnapshot(items: [value], now: now)
        #expect(brief == MorningBriefSnapshot(items: [value], now: now.addingTimeInterval(60)))
        #expect(brief != MorningBriefSnapshot(items: [value], now: now.addingTimeInterval(86_400)))
        #expect(brief != MorningBriefSnapshot(items: [item(number: 1, conflict: true)], now: now))
    }
}
