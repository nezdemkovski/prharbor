import Foundation
import Defaults
import SwiftUI
import Security
import ImageIO
import Testing
@testable import PRHarbor

@Suite("Timeline policy")
struct TimelinePolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func pull() -> Pull {
        Pull(url: URL(string: "https://github.com/example/repo/pull/42")!,
             updatedAt: now.addingTimeInterval(-86_400), createdAt: now.addingTimeInterval(-30 * 86_400),
             title: "HQ-1234: A useful change", number: 42, reviews: Review(totalCount: 0, edges: []),
             author: User(login: "octocat"), repository: Repository(name: "repo", nameWithOwner: "example/repo"),
             labels: Nodes(nodes: []), headRefName: "feature/useful", isDraft: false, isReadByViewer: true)
    }
    private func item(_ pull: Pull, ownComments: Bool = true, snooze: Date? = nil) -> TimelineItem {
        TimelineItem(pull: pull, username: "octocat", now: now, thresholds: [2, 7, 21], bots: ["*[bot]"], ownComments: ownComments, snoozedUntil: snooze)
    }
    @Test func rangesRoundTripWithoutDrawingInTheFuture() {
        for days in [14, 30, 90, 182] {
            let scale = TimelineScale(days: days)
            for age in [0.0, 1, 7, Double(days)] {
                #expect(abs(scale.age(at: scale.position(age: age)) - age) < 0.00001)
            }
            #expect(scale.position(age: -1) == 1)
            #expect(scale.position(age: 999) == 0)
        }
        #expect(TimelineScale(days: 182).position(age: 14) < TimelineScale(days: 90).position(age: 14))
    }
    @Test func thresholdsHaveNoGapsAtTheBoundaries() {
        for (days, expected) in [(0.0, Freshness.fresh), (2, .aging), (7, .stale), (21, .rotting)] {
            #expect(Freshness.allCases.filter { $0.contains(days, thresholds: [2, 7, 21]) } == [expected])
        }
        #expect(TimelinePolicy.validThresholds([7, 2, 0]) == [2, 7, 21])
    }
    @Test func authorCommentsCanBeExcludedWithoutDiscardingOtherActivity() {
        var p = pull()
        p.timelineItems = PullTimelineConnection(nodes: [
            PullTimelineNode(__typename: "PullRequestCommit", commit: TimelineCommit(committedDate: now.addingTimeInterval(-10 * 86_400))),
            PullTimelineNode(__typename: "IssueComment", createdAt: now.addingTimeInterval(-86_400), author: p.author)
        ])
        #expect(item(p).quietDays == 1)
        #expect(item(p, ownComments: false).quietDays == 10)
        p.timelineItems?.nodes.append(PullTimelineNode(__typename: "PullRequestReview", submittedAt: now, state: "CHANGES_REQUESTED", author: User(login: "reviewer")))
        #expect(item(p, ownComments: false).quietDays == 0)
    }
    @Test func automatedCommentsDoNotRefreshQuietTime() {
        var p = pull()
        p.timelineItems = PullTimelineConnection(nodes: [
            PullTimelineNode(__typename: "PullRequestCommit", commit: TimelineCommit(committedDate: now.addingTimeInterval(-10 * 86_400))),
            PullTimelineNode(__typename: "IssueComment", createdAt: now, author: User(login: "checks[bot]"))
        ])
        #expect(item(p).quietDays == 10)
        #expect(item(p).events.count == 2)
    }
    @Test func reviewClockStartsAtLatestPersonalRequest() {
        var p = pull(); p.author = User(login: "someone-else")
        p.timelineItems = PullTimelineConnection(nodes: [
            PullTimelineNode(__typename: "ReviewRequestedEvent", createdAt: now.addingTimeInterval(-9 * 86_400), requestedReviewer: TimelineReviewer(login: "octocat")),
            PullTimelineNode(__typename: "ReviewRequestedEvent", createdAt: now.addingTimeInterval(-5 * 86_400), requestedReviewer: TimelineReviewer(login: "other")),
            PullTimelineNode(__typename: "ReviewRequestedEvent", createdAt: now.addingTimeInterval(-3 * 86_400), requestedReviewer: TimelineReviewer(login: "octocat")),
            PullTimelineNode(__typename: "IssueComment", createdAt: now, author: p.author)
        ])
        #expect(item(p).quietDays == 3)
    }
    @Test func pendingAndUnknownChecksNeverSuggestMerge() {
        var p = pull(); p.reviewDecision = "APPROVED"; p.mergeable = "MERGEABLE"
        func checks(_ state: String) -> CommitsNodes {
            CommitsNodes(nodes: [Commit(commit: CheckSuites(statusCheckRollup: StatusCheckRollup(state: state, contexts: ContextNodes(nodes: [ContextNode(context: "build", state: state)]))))])
        }
        p.commits = checks("PENDING")
        #expect(item(p).nextAction != "Merge on GitHub")
        p.commits = nil
        #expect(item(p).nextAction != "Merge on GitHub")
        p.commits = checks("SUCCESS")
        #expect(item(p).nextAction == "Merge on GitHub")
        p.isDraft = true
        #expect(item(p).nextAction == "Continue draft")
        p.isDraft = false; p.mergeable = "UNKNOWN"
        #expect(item(p).nextAction != "Merge on GitHub")
    }
    @Test func expiredSnoozesAreVisibleAndActiveSnoozesKeepTheirDate() {
        #expect(item(pull(), snooze: now.addingTimeInterval(-1)).snoozedUntil == nil)
        #expect(item(pull(), snooze: now.addingTimeInterval(86_400)).snoozedUntil != nil)
    }
    @Test func botWildcardsDoNotTreatBracketsAsRegularExpressions() {
        #expect(TimelinePolicy.isBot("dependabot[bot]", patterns: ["*[bot]"]))
        #expect(!TimelinePolicy.isBot("robot", patterns: ["*[bot]"]))
        #expect(TimelinePolicy.isBot("NOONA-AI", patterns: ["noona-*"]))
    }
    @Test func queryCombinesRolesFreshnessRepoAgeAndQuietTime() {
        let p = item(pull())
        #expect(p.matches("mine fresh repo >2w idle:0d-2d"))
        #expect(!p.matches("mine repo <2d"))
        #expect(p.matches("HQ-1234 #42 feature/useful"))
        #expect(p.title == "A useful change")
        #expect(p.ticket == "HQ-1234")
    }
    @Test func idleRangeRoundTripsAndKeepsAgeSeparateFromQuietTime() {
        #expect(TimelinePolicy.idleRange("idle:21d+") == 21...Double.infinity)
        #expect(TimelinePolicy.idleRange("idle:21d-7d") == 7...21)
        #expect(TimelinePolicy.idleRange("idle:bad") == nil)
        let value = item(pull())
        #expect(value.matches("mine >2w idle:0d-2d"))
        #expect(!value.matches("mine idle:7d+"))
    }
    @Test func assignedPullRequestsDoNotClaimToWaitForReview() {
        var p = pull(); p.author = User(login: "other")
        let value = TimelineItem(pull: p, username: "octocat", now: now, thresholds: [2, 7, 21], bots: [], ownComments: true, snoozedUntil: nil, reviewRequested: false)
        #expect(value.nextAction == "Open on GitHub")
        #expect(value.standing.hasPrefix("Opened"))
    }
    @Test func ignoresUnavailableEventsAndBotOnlyReviewRequests() throws {
        let connection = try JSONDecoder().decode(PullTimelineConnection.self, from: Data(#"{"nodes":[null]}"#.utf8))
        var p = pull()
        p.timelineItems = connection
        p.reviewRequests = PullReviewRequests(nodes: [PullReviewRequest(requestedReviewer: TimelineReviewer(login: "checks[bot]"))])
        #expect(TimelinePolicy.events(p).count == 1)
        #expect(item(p).nextAction == "Ask for review")
        let team = try JSONDecoder().decode(TimelineReviewer.self, from: Data(#"{"__typename":"Team"}"#.utf8))
        p.reviewRequests?.nodes.append(PullReviewRequest(requestedReviewer: team))
        #expect(item(p).nextAction != "Ask for review")
    }
    @Test func stackWaitsForLowestOpenLayerIncludingOneOutsideTheList() {
        var p = pull()
        let base = StackedPullRequest(id: "base", number: 40, title: "Base", url: URL(string: "https://github.com/example/repo/pull/40")!, state: "OPEN", isDraft: false, headRefName: "base", headRefOid: "abc")
        p.stack = PullRequestStack(id: "stack", number: 3, baseRefName: "main", size: 2, entries: PullRequestStackEntries(nodes: [PullRequestStackEntry(position: 1, pullRequest: base)]))
        p.stackEntry = PullRequestStackPosition(position: 2)
        #expect(item(p).blockedBy?.number == 40)
        #expect(item(p).nextAction == "Go to #40")
        p.stack?.entries?.nodes[0].pullRequest?.state = "MERGED"
        #expect(item(p).blockedBy == nil)
    }
}
