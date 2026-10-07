import Foundation
import Defaults
import Testing
@testable import PRHarbor

@Suite("Service cleanup")
struct ServiceCleanupTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func pull(owner: String = "octocat") -> Pull {
        Pull(url: URL(string: "https://github.com/example/repo/pull/42")!,
             updatedAt: now.addingTimeInterval(-70 * 86_400), createdAt: now.addingTimeInterval(-90 * 86_400),
             title: "Change", number: 42, reviews: Review(totalCount: 0, edges: []),
             author: User(login: owner), repository: Repository(name: "repo", nameWithOwner: "example/repo"),
             labels: Nodes(nodes: []), headRefName: "feature", isDraft: false, isReadByViewer: true)
    }

    private func item(_ pull: Pull, ownComments: Bool = true) -> TimelineItem {
        TimelineItem(pull: pull, username: "octocat", now: now, thresholds: [2, 7, 21],
                     bots: ["*[bot]"], ownComments: ownComments, snoozedUntil: nil)
    }

    @Test(arguments: ["FAILURE", "PENDING"])
    func aggregateOverridesASuccessfulBoundedDetailSlice(_ overall: String) {
        var p = pull()
        p.reviewDecision = "APPROVED"; p.mergeable = "MERGEABLE"
        p.updatedAt = now
        p.commits = CommitsNodes(nodes: [Commit(commit: CheckSuites(
            checkSuites: CheckSuitsNodes(nodes: [CheckSuit(checkRuns: CheckRun(totalCount: 30,
                nodes: [Check(name: "one loaded check", conclusion: "SUCCESS", detailsUrl: p.url)]))]),
            statusCheckRollup: StatusCheckRollup(state: overall)))])
        let value = item(p)
        #expect(value.checks.count == 1)
        #expect(value.ci == ciStatusKind(overall))
        #expect(value.nextAction != "Merge on GitHub")
        p.commits?.nodes[0].commit.statusCheckRollup = nil
        #expect(item(p).ci == nil)
        #expect(item(p).nextAction != "Merge on GitHub")
    }

    @Test(arguments: [BuildType.checks, .commitStatus])
    func bothDetailModesFetchAuthoritativeRollup(_ mode: BuildType) async throws {
        let transport = CleanupQueryTransport()
        let client = try GitHubClient(baseURL: "https://cleanup-query.example", buildType: mode, transport: transport)
        #expect(try await client.fetchPulls(filter: "author:octocat").isEmpty)
        let text = await transport.lastQuery
        #expect(text.contains("statusCheckRollup"))
        #expect(text.contains("state"))
        #expect(text.contains("checkSuites(first: 10)") == (mode == .checks))
        #expect(text.contains("contexts(first: 20)") == (mode == .commitStatus))
        let rollup = try JSONDecoder().decode(StatusCheckRollup.self, from: Data(#"{"state":"PENDING"}"#.utf8))
        #expect(rollup.contexts == nil)
    }

    @Test func truncatedReviewHistoryDoesNotInventAWaitingDate() {
        var p = pull(owner: "teammate")
        p.timelineItems = PullTimelineConnection(nodes: [PullTimelineNode(__typename: "IssueComment", createdAt: now,
            author: User(login: "teammate"))], pageInfo: PullTimelinePageInfo(hasPreviousPage: true))
        let unknown = item(p)
        #expect(!unknown.hasKnownQuietPeriod)
        #expect(unknown.standing.contains("unknown"))
        #expect(!unknown.matches("stale"))
        #expect(!unknown.matches("idle:0d+"))
        #expect(TimelineNotificationPolicy.waitingForReview([unknown]).count == 1) // Request membership is known even when its date is not.
        p.timelineItems?.nodes.append(PullTimelineNode(__typename: "ReviewRequestedEvent",
            createdAt: now.addingTimeInterval(-3 * 86_400), requestedReviewer: TimelineReviewer(login: "octocat")))
        #expect(item(p).hasKnownQuietPeriod)
        #expect(item(p).quietDays == 3)
    }

    @Test func truncatedExcludedActivityCannotTriggerRottingOrAgeBasedActions() {
        var p = pull()
        p.reviewRequests = PullReviewRequests(nodes: [PullReviewRequest(requestedReviewer: TimelineReviewer(login: "reviewer"))])
        p.timelineItems = PullTimelineConnection(nodes: [
            PullTimelineNode(__typename: "IssueComment", createdAt: now, author: p.author),
            PullTimelineNode(__typename: "IssueComment", createdAt: now, author: User(login: "checks[bot]"))
        ], pageInfo: PullTimelinePageInfo(hasPreviousPage: true))
        let unknown = item(p, ownComments: false)
        #expect(!unknown.hasKnownQuietPeriod)
        #expect(unknown.freshness != .rotting)
        #expect(unknown.nextAction != "Revive or close")
        #expect(unknown.nextAction != "Nudge reviewers")
        #expect(!unknown.matches("dead"))
        #expect(TimelineNotificationPolicy.rottingOwned([unknown]).isEmpty)
        p.timelineItems?.nodes.append(PullTimelineNode(__typename: "PullRequestCommit", commit: TimelineCommit(committedDate: now.addingTimeInterval(-22 * 86_400))))
        #expect(item(p, ownComments: false).hasKnownQuietPeriod)
        #expect(TimelineNotificationPolicy.rottingOwned([item(p, ownComments: false)]).count == 1)
    }

    @Test func projectionPreservesReviewMembershipAcrossCategoryVisibilityAndDeduplicates() {
        let edge = Edge(node: pull(owner: "teammate"))
        let input = TimelineInput(assigned: [edge], created: [], requested: [edge], includeRequested: false,
            username: "octocat", now: now, thresholds: [2, 7, 21], bots: [], ownComments: true, snoozed: [:])
        #expect(input.makeItems().count == 1)
        #expect(input.makeItems().first?.reviewRequested == true)
        let all = TimelineInput(assigned: [edge], created: [edge], requested: [edge],
            username: "octocat", now: now, thresholds: [2, 7, 21], bots: [], ownComments: true, snoozed: [:])
        #expect(all.makeItems().count == 1)
    }

    @Test func notificationBaselineThresholdsSnoozeAndDayWindowAreExplicit() {
        let rotting = item(pull())
        #expect(TimelineNotificationPolicy.newlyRotting([rotting], previousIDs: nil, previousThresholds: nil, thresholds: [2, 7, 21]).isEmpty)
        #expect(TimelineNotificationPolicy.newlyRotting([rotting], previousIDs: [], previousThresholds: [1, 2, 3], thresholds: [2, 7, 21]).isEmpty)
        #expect(TimelineNotificationPolicy.newlyRotting([rotting], previousIDs: [], previousThresholds: [2, 7, 21], thresholds: [2, 7, 21]).count == 1)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9, minute: 5))!
        #expect(TimelineNotificationPolicy.summaryDay(now: morning, calendar: calendar, scheduledMinutes: 540, refreshMinutes: 5, lastDay: "") == "2026-10-5")
        #expect(TimelineNotificationPolicy.summaryDay(now: morning, calendar: calendar, scheduledMinutes: 540, refreshMinutes: 5, lastDay: "2026-10-5") == nil)
        #expect(TimelineNotificationPolicy.summaryDay(now: morning.addingTimeInterval(300), calendar: calendar, scheduledMinutes: 540, refreshMinutes: 5, lastDay: "") == nil)
    }

    @Test func snoozesWakeOnlyForExpiryOrObservedOtherAccountCommentsAfterBaseline() {
        var p = pull()
        let url = p.url.absoluteString, until = now.addingTimeInterval(86_400).timeIntervalSince1970
        let baseline = now.addingTimeInterval(-100).timeIntervalSince1970
        p.timelineItems = PullTimelineConnection(nodes: [PullTimelineNode(__typename: "IssueComment", createdAt: now,
            author: User(login: "OCTOCAT"))], pageInfo: PullTimelinePageInfo(hasPreviousPage: true))
        func reconcile(_ wake: Bool = true, date: Date? = nil) -> (snoozed: [String: Double], activity: [String: Double]) {
            TimelineSnoozePolicy.reconcile(edges: [Edge(node: p)], snoozed: [url: until], activity: [url: baseline],
                                          now: date ?? now, wakeOnComment: wake, username: "octocat")
        }
        #expect(reconcile().snoozed[url] == until)
        p.timelineItems?.nodes[0]?.author = User(login: "reviewer")
        #expect(reconcile(false).snoozed[url] == until)
        #expect(reconcile().snoozed.isEmpty)
        #expect(reconcile().activity.isEmpty)
        p.timelineItems?.nodes = []
        #expect(reconcile().snoozed[url] == until) // Truncation alone cannot wake it.
        #expect(reconcile(date: now.addingTimeInterval(86_400)).snoozed.isEmpty)
    }
}

private actor CleanupQueryTransport: GitHubAPITransport {
    var lastQuery = ""
    func api(_ endpoint: String, body: Data?) async throws -> Data {
        lastQuery = try query(from: body!)
        return Data(#"{"data":{"search":{"edges":[],"issueCount":0,"pageInfo":{"hasNextPage":false,"endCursor":null}}}}"#.utf8)
    }
}

@Suite("Mutation revalidation", .serialized)
@MainActor
struct MutationRevalidationTests {
    private func stack() -> PullRequestStack {
        PullRequestStack(id: "test-stack", number: 1, baseRefName: "main", size: 2,
            entries: PullRequestStackEntries(nodes: (1...2).map { position in
                PullRequestStackEntry(position: position, pullRequest: StackedPullRequest(id: "p\(position)", number: position,
                    title: "Layer", url: URL(string: "https://github.com/example/repo/pull/\(position)")!,
                    state: "OPEN", isDraft: false, headRefName: "branch\(position)", headRefOid: "oid\(position)", mergeable: "MERGEABLE"))
            }))
    }

    @Test(arguments: [false, true])
    func rebaseDuringRefreshSupersedesOldDataEvenAfterPartialFailure(_ partial: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = GitHubSession(connection: GitHubCLIConnection(executablePath: "/unused", username: "octocat", apiBaseURL: Defaults[.githubApiBaseUrl]))
        let sample = try #require(TimelinePreviewData.items(now: .now).first { $0.pull.stack == nil })
        let transport = CleanupMutationTransport(edge: Edge(node: sample.pull), partial: partial)
        var calls = 0
        let store = PullRequestStore(startAutomatically: false, session: session, cache: PullSnapshotCache(directory: directory),
            clientProvider: { baseURL, buildType in
                calls += 1
                return try GitHubClient(baseURL: baseURL, buildType: buildType,
                    transport: CleanupMutationAdapter(transport: transport, revision: calls))
            })
        store.refresh()
        for _ in 0..<200 {
            if await transport.oldQueries > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(store.isLoading)
        #expect(await transport.oldQueries > 0)
        if partial {
            do {
                _ = try await store.rebaseStack(stack())
                Issue.record("Expected partial failure")
            } catch let error as StackRebaseError {
                guard case .partial(let completed, let total, _, _) = error else {
                    Issue.record("Expected partial progress, got \(error)"); await transport.releaseOld(); return
                }
                #expect(completed == 1)
                #expect(total == 2)
            }
        } else {
            #expect(try await store.rebaseStack(stack()).rebasedCount == 2)
        }
        for _ in 0..<200 where store.isLoading { try await Task.sleep(for: .milliseconds(5)) }
        #expect(calls == 3) // Refresh, injected rebase client, forced revalidation.
        #expect(await transport.mutations == 2)
        #expect(store.lastSyncedAt != nil)
        #expect(store.timelineInput().makeItems().allSatisfy { $0.pull.title == "After rebase" })
        #expect(!store.isEmpty)
        await transport.releaseOld()
        try await Task.sleep(for: .milliseconds(30))
        #expect(store.timelineInput().makeItems().allSatisfy { $0.pull.title == "After rebase" })
        store.clear()
        await store.loadCachedSnapshot()
    }

    @Test func accountChangeDuringClientCreationPreventsMutationAndRevalidation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = GitHubSession(connection: GitHubCLIConnection(executablePath: "/unused", username: "octocat", apiBaseURL: Defaults[.githubApiBaseUrl]))
        let gate = PullFetchGate(), transport = CleanupQueryTransport()
        var calls = 0
        let store = PullRequestStore(startAutomatically: false, session: session, cache: PullSnapshotCache(directory: directory),
            clientProvider: { baseURL, buildType in
                calls += 1
                await gate.wait()
                return try GitHubClient(baseURL: baseURL, buildType: buildType, transport: transport)
            })
        let task = Task { try await store.rebaseStack(stack()) }
        for _ in 0..<200 where calls == 0 { try await Task.sleep(for: .milliseconds(5)) }
        session.useCLI(GitHubCLIConnection(executablePath: "/unused", username: "another-account", apiBaseURL: Defaults[.githubApiBaseUrl]))
        await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(calls == 1)
        #expect(await transport.lastQuery.isEmpty)
        #expect(store.isEmpty)
        #expect(store.lastSyncedAt == nil)
    }

    @Test func accountMismatchRetainsItsOriginalErrorAndClearsOldData() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = GitHubSession(connection: GitHubCLIConnection(executablePath: "/unused", username: "octocat", apiBaseURL: Defaults[.githubApiBaseUrl]))
        let sample = try #require(TimelinePreviewData.items(now: .now).first)
        let store = PullRequestStore(startAutomatically: false, session: session, cache: PullSnapshotCache(directory: directory),
            clientProvider: { _, _ in throw GitHubCLIError.accountChanged })
        store.createdPulls = [Edge(node: sample.pull)]
        await #expect(throws: GitHubCLIError.self) { try await store.rebaseStack(stack()) }
        #expect(store.isEmpty)
        #expect(store.error == GitHubCLIError.accountChanged.localizedDescription)
        #expect(!store.isLoading)
        await store.loadCachedSnapshot()
    }
}

private struct CleanupMutationAdapter: GitHubAPITransport {
    let transport: CleanupMutationTransport
    let revision: Int
    func api(_ endpoint: String, body: Data?) async throws -> Data {
        try await transport.api(body: body!, revision: revision)
    }
}

private actor CleanupMutationTransport {
    let edge: Edge
    let partial: Bool
    var oldQueries = 0
    var mutations = 0
    private var oldWaiters: [CheckedContinuation<Void, Never>] = []
    private var oldReleased = false
    init(edge: Edge, partial: Bool) { self.edge = edge; self.partial = partial }

    func api(body: Data, revision: Int) async throws -> Data {
        let text = try query(from: body)
        if text.contains("mutation RebasePullRequestBranch") {
            mutations += 1
            if partial && mutations == 2 { throw URLError(.notConnectedToInternet) }
            return Data(#"{"data":{"updatePullRequestBranch":{"pullRequest":{"id":"done","headRefOid":"new"}}}}"#.utf8)
        }
        if revision == 1 {
            oldQueries += 1
            if !oldReleased { await withCheckedContinuation { oldWaiters.append($0) } }
        }
        var fetched = edge
        fetched.node.title = revision == 1 ? "Before rebase" : "After rebase"
        let response = GraphQLSearchResponse(data: ResponseData(search: Search(edges: [fetched], issueCount: 1,
            pageInfo: PageInfo(hasNextPage: false, endCursor: nil))))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(response)
    }

    func releaseOld() {
        oldReleased = true
        oldWaiters.forEach { $0.resume() }
        oldWaiters = []
    }
}
