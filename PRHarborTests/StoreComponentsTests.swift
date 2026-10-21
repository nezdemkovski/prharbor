import Foundation
import Testing
@testable import PRHarbor

@Suite("Store components")
struct StoreComponentsTests {
    private let scope = PullSnapshotScope(username: "octocat", baseURL: "https://api.github.com", buildType: .none,
                                          hideDrafts: false, assigned: true, created: false, requested: true)

    @Test func searchesQueryTheConnectedAccountAndFollowTheScope() {
        #expect(PullSearch.allCases.map { $0.filter(username: "octocat") }
                == ["assignee:octocat", "author:octocat", "review-requested:octocat"])
        #expect(PullSearch.allCases.filter { $0.isEnabled(in: scope) } == [.assigned, .requested])
    }

    @Test @MainActor func aRemovalQueuedAfterASaveWins() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = SnapshotStorage(cache: PullSnapshotCache(directory: directory))
        let snapshot = PullSnapshot(scope: scope, syncedAt: .now, assigned: [], created: [], requested: [])
        await storage.save(snapshot).value
        #expect(await storage.load(scope: scope) != nil)
        storage.save(snapshot)
        storage.remove(scope: scope)
        #expect(await storage.load(scope: scope) == nil)
    }

    @Test func menuBarCountFollowsTheCounterType() {
        #expect(CounterType.assigned.count(items: [], assigned: 3, created: 5, requested: 7) == 3)
        #expect(CounterType.reviewRequested.count(items: [], assigned: 3, created: 5, requested: 7) == 7)
        #expect(CounterType.none.count(items: [], assigned: 3, created: 5, requested: 7) == 0)
    }
}
