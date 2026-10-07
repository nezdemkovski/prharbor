import Foundation
import Defaults
import SwiftUI
import Security
import ImageIO
import Testing
@testable import PRHarbor

@Suite("Progressive pull loading", .serialized)
struct ProgressivePullLoadingTests {
    @Test @MainActor func showsReadyPullsBeforeTheSlowCategoryAndKeepsThemOnFailure() async throws {
        let gate = PullFetchGate()
        let sample = try #require(TimelinePreviewData.items(now: .now).first { $0.pull.stack == nil })
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = GitHubSession(connection: GitHubCLIConnection(executablePath: "/unused", username: "progress-user",
            apiBaseURL: GitHubSession.shared.cliConnection?.apiBaseURL ?? "https://api.github.com"))
        let store = PullRequestStore(startAutomatically: false, session: session, cache: PullSnapshotCache(directory: directory),
            clientProvider: { baseURL, build in
                try GitHubClient(baseURL: baseURL, buildType: build,
                    transport: ProgressivePullTransport(gate: gate, edge: Edge(node: sample.pull)))
            })
        store.refresh()
        for _ in 0..<100 where store.assignedPulls.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(store.isLoading)
        #expect(store.assignedPulls.count == 1)
        await gate.release()
        for _ in 0..<100 where store.isLoading { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!store.isLoading)
        #expect(store.error != nil)
        #expect(store.assignedPulls.first?.node.url == sample.pull.url)
        #expect(store.lastSyncedAt == nil) // A partial fetch never claims a completed synchronization.
        let cache = PullSnapshotCache(directory: directory)
        var saved: PullSnapshot?
        for _ in 0..<100 {
            saved = await cache.load(scope: store.snapshotScope)
            if saved != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let partial = try #require(saved)
        #expect(!partial.isComplete)
        #expect(!partial.isFresh(at: .now, interval: 300))
        #expect(partial.assigned.first?.node.url == sample.pull.url)
        let restored = PullRequestStore(startAutomatically: false, session: session, cache: cache)
        await restored.loadCachedSnapshot()
        #expect(restored.assignedPulls.count == 1)
        #expect(restored.hasIncompleteData)
    }

    @Test @MainActor func clearingAfterSuccessCannotLeaveALateDiskSnapshot() async throws {
        let gate = PullFetchGate()
        let sample = try #require(TimelinePreviewData.items(now: .now).first { $0.pull.stack == nil })
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PullSnapshotCache(directory: directory)
        let session = GitHubSession(connection: GitHubCLIConnection(executablePath: "/unused", username: "progress-user",
            apiBaseURL: GitHubSession.shared.cliConnection?.apiBaseURL ?? "https://api.github.com"))
        let store = PullRequestStore(startAutomatically: false, session: session, cache: cache,
            clientProvider: { baseURL, build in
                try GitHubClient(baseURL: baseURL, buildType: build,
                    transport: ProgressivePullTransport(gate: gate, edge: Edge(node: sample.pull), failRequested: false))
            })
        store.refresh()
        await gate.release()
        for _ in 0..<100 where store.isLoading { try await Task.sleep(for: .milliseconds(5)) }
        #expect(store.lastSyncedAt != nil)
        let scope = store.snapshotScope
        store.clear()
        await store.loadCachedSnapshot() // Waits for a pending write and the subsequent removal.
        #expect(store.lastSyncedAt == nil)
        #expect(await cache.load(scope: scope) == nil)
    }

    @Test @MainActor func clearingTheStoreDiscardsLateCategoryResults() async throws {
        let gate = PullFetchGate()
        let sample = try #require(TimelinePreviewData.items(now: .now).first { $0.pull.stack == nil })
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = GitHubSession(connection: GitHubCLIConnection(executablePath: "/unused", username: "progress-user",
            apiBaseURL: GitHubSession.shared.cliConnection?.apiBaseURL ?? "https://api.github.com"))
        let store = PullRequestStore(startAutomatically: false, session: session, cache: PullSnapshotCache(directory: directory),
            clientProvider: { baseURL, build in
                try GitHubClient(baseURL: baseURL, buildType: build,
                    transport: ProgressivePullTransport(gate: gate, edge: Edge(node: sample.pull)))
            })
        store.refresh()
        for _ in 0..<100 where store.assignedPulls.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        store.clear()
        await gate.release()
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.isEmpty)
        #expect(store.error == nil)
        #expect(store.lastSyncedAt == nil)
    }
}
