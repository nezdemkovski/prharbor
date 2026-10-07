#if DEBUG || PRHARBOR_TEST_FIXTURES
import SwiftUI
import Defaults

@MainActor
enum TimelinePreviewData {
    static func items(now: Date) -> [TimelineItem] {
        func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
        guard let source = try? JSONDecoder().decode([PrototypePull].self, from: Data(prototypeJSON.utf8)) else {
            assertionFailure("The bundled timeline preview fixture must be valid JSON")
            return []
        }
        var pulls = source.map { sample in
            let ci = ["pass": "SUCCESS", "fail": "FAILURE", "pending": "PENDING"][sample.ci] ?? "SUCCESS"
            let review = ["approved": "APPROVED", "changes": "CHANGES_REQUESTED"][sample.review]
            let events: [PullTimelineNode?] = sample.events.compactMap { event in
                let user = event.who.map { User(login: $0) }
                switch event.type {
                case "commit": return PullTimelineNode(__typename: "PullRequestCommit", commit: TimelineCommit(committedDate: ago(event.t)))
                case "comment": return PullTimelineNode(__typename: "IssueComment", createdAt: ago(event.t), author: user)
                case "approved", "changes": return PullTimelineNode(__typename: "PullRequestReview", submittedAt: ago(event.t), state: event.type == "approved" ? "APPROVED" : "CHANGES_REQUESTED", author: user)
                case "requested": return PullTimelineNode(__typename: "ReviewRequestedEvent", createdAt: ago(event.t), requestedReviewer: TimelineReviewer(login: event.who))
                case "ci_fail": return PullTimelineNode(__typename: "IssueComment", createdAt: ago(event.t))
                default: return nil
                }
            }
            return Pull(url: URL(string: "https://github.com/acme/\(sample.repo)/pull/\(sample.num)")!, updatedAt: ago(sample.events.map(\.t).min() ?? sample.created), createdAt: ago(sample.created), title: sample.title, number: sample.num,
                        deletions: sample.del, additions: sample.add, reviews: Review(totalCount: review == "APPROVED" ? 1 : 0, edges: []), author: User(login: sample.author), repository: Repository(name: sample.repo, nameWithOwner: "acme/\(sample.repo)"),
                        commits: CommitsNodes(nodes: [Commit(commit: CheckSuites(statusCheckRollup: StatusCheckRollup(state: ci, contexts: ContextNodes(nodes: [ContextNode(context: "build", state: ci)]))))]),
                        labels: Nodes(nodes: []), headRefName: "", isDraft: sample.draft ?? false, isReadByViewer: true, reviewDecision: review,
                        mergeable: sample.conflict == true ? "CONFLICTING" : "MERGEABLE", baseRefName: "main", timelineItems: PullTimelineConnection(nodes: events),
                        reviewRequests: PullReviewRequests(nodes: sample.reviewers.map { PullReviewRequest(requestedReviewer: TimelineReviewer(login: $0)) }))
        }
        for id in Set(source.compactMap { $0.stack?.id }) {
            let indexes = source.indices.filter { source[$0].stack?.id == id }
            let entries = indexes.map { index in
                PullRequestStackEntry(position: source[index].stack!.pos, pullRequest: StackedPullRequest(id: "preview-\(index)", number: pulls[index].number, title: pulls[index].title, url: pulls[index].url, state: "OPEN", isDraft: pulls[index].isDraft, headRefName: pulls[index].headRefName, headRefOid: "preview", reviewDecision: pulls[index].reviewDecision, mergeable: pulls[index].mergeable))
            }
            for index in indexes {
                pulls[index].stack = PullRequestStack(id: id, number: source[index].stack!.num, baseRefName: "main", size: indexes.count, entries: PullRequestStackEntries(nodes: entries))
                pulls[index].stackEntry = PullRequestStackPosition(position: source[index].stack!.pos)
            }
        }
        return pulls.enumerated().map { index, pull in
            TimelineItem(pull: pull, username: "yuri", now: now, thresholds: [2, 7, 21], bots: ["dependabot", "*[bot]"], ownComments: true,
                         snoozedUntil: source[index].snooze.map { ago($0) }, reviewRequested: source[index].reviewers.contains("yuri"))
        }

    }
    private struct PrototypePull: Decodable {
        let repo: String, num: Int, title: String, author: String, created: Double, ci: String, review: String, reviewers: [String], add: Int, del: Int
        var draft: Bool?, conflict: Bool?, snooze: Double?, stack: Stack?
        let events: [Event]
        struct Event: Decodable { let t: Double, type: String; var who: String? }
        struct Stack: Decodable { let id: String, num: Int, pos: Int, base: String }
    }
    // Identical public mock data from prototype/timeline.html; never reads private data.js.
    private static let prototypeJSON = #"""
    [
    {"id":1,"repo":"prharbor","num":418,"title":"Timeline view for open pull requests","author":"yuri","created":2.1,"draft":true,"ci":"pass","review":"none","reviewers":[],"add":812,"del":140,"events":[{"t":2.1,"type":"opened"},{"t":1.4,"type":"commit"},{"t":0.3,"type":"commit"}]},
    {"id":2,"repo":"prharbor","num":412,"title":"Harden token refresh in device flow","author":"yuri","created":9.2,"ci":"pass","review":"approved","reviewers":["anna"],"add":96,"del":31,"events":[{"t":9.2,"type":"opened"},{"t":8.5,"type":"commit"},{"t":6.8,"type":"comment","who":"anna"},{"t":6,"type":"commit"},{"t":3.2,"type":"approved","who":"anna"}]},
    {"id":3,"repo":"noona-web","num":2291,"title":"Booking widget: timezone-aware slots","author":"yuri","created":34,"ci":"pass","review":"changes","reviewers":["marek","lena"],"add":420,"del":198,"events":[{"t":34,"type":"opened"},{"t":31,"type":"commit"},{"t":27.5,"type":"commit"},{"t":22.4,"type":"changes","who":"marek"},{"t":21.8,"type":"comment","who":"lena"}]},
    {"id":4,"repo":"noona-web","num":2304,"title":"Migrate calendar to Temporal API","author":"yuri","created":18,"ci":"fail","review":"none","reviewers":["anna"],"add":1310,"del":902,"events":[{"t":18,"type":"opened"},{"t":16.2,"type":"commit"},{"t":14.1,"type":"ci_fail"}]},
    {"id":5,"repo":"noona-api","num":881,"title":"Idempotency keys for payment intents","author":"yuri","created":96,"ci":"pass","review":"none","conflict":true,"reviewers":["marek"],"add":244,"del":12,"events":[{"t":96,"type":"opened"},{"t":90,"type":"commit"},{"t":84,"type":"commit"},{"t":71,"type":"comment","who":"marek"}]},
    {"id":6,"repo":"noona-api","num":902,"title":"Extract slot engine into module","author":"yuri","created":12.2,"ci":"pass","review":"approved","reviewers":["tomas"],"add":380,"del":344,"stack":{"id":"s37","num":37,"pos":1,"base":"main"},"events":[{"t":12.2,"type":"opened"},{"t":11,"type":"commit"},{"t":4.4,"type":"approved","who":"tomas"}]},
    {"id":7,"repo":"noona-api","num":903,"title":"Cache computed slots per venue","author":"yuri","created":11.4,"ci":"pass","review":"none","reviewers":["tomas"],"add":172,"del":20,"stack":{"id":"s37","num":37,"pos":2,"base":"main"},"events":[{"t":11.4,"type":"opened"},{"t":10.2,"type":"commit"},{"t":6.1,"type":"comment","who":"tomas"}]},
    {"id":8,"repo":"noona-api","num":904,"title":"Expose /slots endpoint","author":"yuri","created":10.5,"draft":true,"ci":"pending","review":"none","reviewers":[],"add":88,"del":4,"stack":{"id":"s37","num":37,"pos":3,"base":"main"},"events":[{"t":10.5,"type":"opened"}]},
    {"id":9,"repo":"noona-web","num":2310,"title":"Settings: notification preferences","author":"anna","created":5.3,"ci":"pass","review":"requested","reviewers":["yuri"],"add":260,"del":45,"events":[{"t":5.3,"type":"opened"},{"t":5.1,"type":"requested","who":"yuri"},{"t":3.9,"type":"commit"},{"t":1.2,"type":"commit"}]},
    {"id":10,"repo":"homelab","num":57,"title":"Bump cilium to 1.19","author":"tomas","created":0.8,"ci":"pass","review":"requested","reviewers":["yuri"],"add":6,"del":6,"events":[{"t":0.8,"type":"opened"},{"t":0.7,"type":"requested","who":"yuri"}]},
    {"id":14,"repo":"noona-api","num":889,"title":"Webhook delivery log table","author":"marek","created":27,"ci":"pass","review":"requested","reviewers":["yuri"],"add":210,"del":3,"stack":{"id":"s41","num":41,"pos":1,"base":"main"},"events":[{"t":27,"type":"opened"},{"t":26.8,"type":"requested","who":"yuri"},{"t":20.5,"type":"commit"}]},
    {"id":11,"repo":"noona-api","num":890,"title":"Rate-limit webhook retries","author":"marek","created":26,"ci":"pass","review":"requested","reviewers":["yuri","lena"],"add":133,"del":58,"stack":{"id":"s41","num":41,"pos":2,"base":"main"},"events":[{"t":26,"type":"opened"},{"t":25.6,"type":"requested","who":"yuri"},{"t":19,"type":"comment","who":"lena"},{"t":12.3,"type":"commit"}]},
    {"id":12,"repo":"dotfiles","num":19,"title":"zsh: lazy-load nvm","author":"yuri","created":48,"ci":"pass","review":"none","reviewers":[],"add":22,"del":9,"events":[{"t":48,"type":"opened"}]},
    {"id":13,"repo":"noona-web","num":2279,"title":"Experiment: new onboarding copy","author":"yuri","created":40,"ci":"pass","review":"none","reviewers":["lena"],"add":58,"del":41,"snooze":-4,"events":[{"t":40,"type":"opened"},{"t":37,"type":"commit"},{"t":30,"type":"comment","who":"lena"}]},
    {"id":15,"repo":"noona-web","num":2201,"title":"Bump vite from 5.4.6 to 6.4.2","author":"dependabot","created":120,"ci":"pass","review":"none","reviewers":[],"add":4,"del":4,"events":[{"t":120,"type":"opened"}]},
    {"id":16,"repo":"noona-api","num":812,"title":"Tune mongo pool size","author":"lena","created":44,"ci":"pass","review":"none","reviewers":[],"add":3,"del":3,"events":[{"t":44,"type":"opened"}]}
    ]
    """#

}

#endif

#if DEBUG
#Preview("PR timeline") {
    let store = PullRequestStore(startAutomatically: false)
    let now = Date()
    TimelinePanel(store: store, now: now, onSettings: {}, onAbout: {}, onQuit: {}, previewItems: TimelinePreviewData.items(now: now))
        .frame(width: 780)
}
#endif

#if DEBUG
struct TimelinePreviewHost: View {
    let store: PullRequestStore
    @Environment(\.openSettings) private var openSettings
    @State private var now = Date()
    @Default(.snoozedPulls) private var snoozed
    @Default(.freshnessThresholds) private var thresholds
    @Default(.ownCommentsCount) private var comments
    @Default(.botAccounts) private var bots
    @Default(.hideDrafts) private var hideDrafts
    @Default(.showCreated) private var showCreated
    @Default(.showRequested) private var showRequested
    private var items: [TimelineItem] {
        TimelinePreviewData.items(now: now).filter { ($0.isMine ? showCreated : showRequested) && (!hideDrafts || !$0.pull.isDraft) }.map { item in
            TimelineItem(pull: item.pull, username: "yuri", now: now, thresholds: thresholds,
                         bots: bots, ownComments: comments,
                         snoozedUntil: snoozed[item.id].map { Date(timeIntervalSince1970: $0) } ?? item.snoozedUntil, reviewRequested: item.reviewRequested)
        }
    }
    var body: some View {
        TimelinePanel(store: store, now: now, onSettings: { openSettings() }, onAbout: {}, onQuit: { NSApp.terminate(nil) }, previewItems: items)
            .frame(width: 780)
            .background(Color(nsColor: .windowBackgroundColor))
            .onAppear {
                let items = TimelinePreviewData.items(now: now)
                store.createdPulls = items.filter(\.isMine).map { Edge(node: $0.pull) }
                store.reviewRequestedPulls = items.filter { !$0.isMine }.map { Edge(node: $0.pull) }
                NSApp.activate()
            }
    }
}
#endif
