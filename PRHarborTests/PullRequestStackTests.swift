import Foundation
import Defaults
import SwiftUI
import Security
import ImageIO
import Testing
@testable import PRHarbor

struct PullRequestStackTests {
    @Test
    func decodesLayerOrderAndTrunk() throws {
        let data = Data(#"""
        {
            "id":"PRS_example",
            "number":42,
            "baseRefName":"main",
            "size":2,
            "entries":{"nodes":[
                {"position":1,"pullRequest":{"id":"PR_101","number":101,"title":"Foundation","url":"https://github.com/example/repo/pull/101","state":"OPEN","isDraft":false,"headRefName":"stack/foundation","headRefOid":"oid-101","reviewDecision":"APPROVED","mergeable":"MERGEABLE"}},
                {"position":2,"pullRequest":{"id":"PR_102","number":102,"title":"UI","url":"https://github.com/example/repo/pull/102","state":"OPEN","isDraft":true,"headRefName":"stack/ui","headRefOid":"oid-102","reviewDecision":null,"mergeable":"UNKNOWN"}}
            ]}
        }
        """#.utf8)

        let stack = try JSONDecoder().decode(PullRequestStack.self, from: data)

        #expect(stack.number == 42)
        #expect(stack.baseRefName == "main")
        #expect(stack.size == 2)
        let entries = try #require(stack.entries?.nodes)
        #expect(entries.map(\.position) == [1, 2])
        #expect(entries[1].pullRequest?.isDraft == true)
    }

    @Test
    func groupsAStackAtItsFirstSortedOccurrenceAndOrdersItsLayers() throws {
        let stack = PullRequestStack(
            id: "PRS_example",
            number: 42,
            baseRefName: "main",
            size: 5
        )
        let shuffledPositions = [5, 2, 4, 1, 3]
        let stackEdges = try shuffledPositions.map { position in
            try edge(number: 100 + position, stack: stack, position: position)
        }
        let standalone = try edge(number: 200)

        let groups = groupPullsForDisplay([stackEdges[0], standalone] + stackEdges.dropFirst())

        #expect(groups.count == 2)
        #expect(groups[0].id == stack.id)
        #expect(groups[0].edges.compactMap(\.node.stackEntry?.position) == [5, 4, 3, 2, 1])
        #expect(groups[1].edges.first?.node.number == 200)
    }

    private func edge(
        number: Int,
        stack: PullRequestStack? = nil,
        position: Int? = nil
    ) throws -> Edge {
        var pull = Pull(
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
        pull.stack = stack
        pull.stackEntry = position.map { PullRequestStackPosition(position: $0) }
        return Edge(node: pull)
    }
}
