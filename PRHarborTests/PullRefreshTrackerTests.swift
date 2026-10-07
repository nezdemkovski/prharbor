import Foundation
import Defaults
import SwiftUI
import Security
import ImageIO
import Testing
@testable import PRHarbor

struct PullRefreshTrackerTests {
    @Test
    func reenabledCategoryEstablishesABaselineBeforeNotifying() throws {
        var tracker = PullRefreshTracker()
        let first = Edge(node: try pull(number: 1))
        let second = Edge(node: try pull(number: 2))
        let third = Edge(node: try pull(number: 3))

        #expect(tracker.update(edges: [first], fetched: true, canNotify: false).isEmpty)
        #expect(tracker.update(edges: [], fetched: false, canNotify: true).isEmpty)
        #expect(tracker.update(edges: [first, second], fetched: true, canNotify: true).isEmpty)
        #expect(tracker.update(edges: [first, second, third], fetched: true, canNotify: true) == [third.node])
    }

    private func pull(number: Int) throws -> Pull {
        Pull(
            url: try #require(URL(string: "https://github.com/example/repo/pull/\(number)")),
            updatedAt: .now,
            createdAt: .now,
            title: "PR \(number)",
            number: number,
            deletions: nil,
            additions: nil,
            reviews: Review(totalCount: 0, edges: []),
            author: nil,
            repository: Repository(name: "repo", nameWithOwner: "example/repo"),
            commits: nil,
            labels: Nodes(nodes: []),
            headRefName: "feature/\(number)",
            isDraft: false,
            isReadByViewer: false,
            reviewDecision: nil,
            mergeable: nil
        )
    }
}
