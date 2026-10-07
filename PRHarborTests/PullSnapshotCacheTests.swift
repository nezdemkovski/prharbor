import Foundation
import Defaults
import SwiftUI
import Security
import ImageIO
import Testing
@testable import PRHarbor

@Suite("Persistent pull cache", .serialized)
struct PullSnapshotCacheTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func scope(username: String = "octocat", host: String = "https://api.github.com", hideDrafts: Bool = false) -> PullSnapshotScope {
        PullSnapshotScope(username: username, baseURL: host, buildType: .checks,
                          hideDrafts: hideDrafts, assigned: true, created: true, requested: true)
    }
    private func snapshot(scope: PullSnapshotScope, date: Date) -> PullSnapshot {
        PullSnapshot(scope: scope, syncedAt: date, assigned: [], created: [], requested: [])
    }

    @Test func restoresAcrossCacheInstancesAndIsolatesAccountHostAndQuerySettings() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = PullSnapshotCache(directory: directory)
        await writer.save(snapshot(scope: scope(), date: now))
        let reader = PullSnapshotCache(directory: directory)
        #expect(await reader.load(scope: scope(), now: now)?.syncedAt == now)
        #expect(await reader.load(scope: scope(username: "other"), now: now) == nil)
        #expect(await reader.load(scope: scope(host: "https://enterprise.example/api/v3"), now: now) == nil)
        #expect(await reader.load(scope: scope(hideDrafts: true), now: now) == nil)
        let permissions = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("snapshot-v1.json").path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test func rejectsExpiredFutureUnknownVersionAndCorruptSnapshots() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PullSnapshotCache(directory: directory)
        await cache.save(snapshot(scope: scope(), date: now.addingTimeInterval(-8 * 86_400)))
        #expect(await cache.load(scope: scope(), now: now) == nil)
        await cache.save(snapshot(scope: scope(), date: now.addingTimeInterval(1)))
        #expect(await cache.load(scope: scope(), now: now) == nil)
        var unknown = snapshot(scope: scope(), date: now)
        unknown.version = 99
        await cache.save(unknown)
        #expect(await cache.load(scope: scope(), now: now) == nil)
        try Data("broken".utf8).write(to: directory.appendingPathComponent("snapshot-v1.json"))
        #expect(await cache.load(scope: scope(), now: now) == nil)
    }

    @Test @MainActor func staleSnapshotRemainsVisibleDuringBackgroundRevalidation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PullSnapshotCache(directory: directory)
        let session = GitHubSession(connection: GitHubCLIConnection(executablePath: "/unused", username: "cache-user",
            apiBaseURL: GitHubSession.shared.cliConnection?.apiBaseURL ?? "https://api.github.com"))
        let store = PullRequestStore(startAutomatically: false, session: session, cache: cache, clientProvider: { _, _ in
            try await Task.sleep(for: .milliseconds(30))
            throw URLError(.notConnectedToInternet)
        })
        let date = Date.now.addingTimeInterval(-6 * 86_400)
        let edges = TimelinePreviewData.items(now: .now).prefix(3).map { Edge(node: $0.pull) }
        await cache.save(PullSnapshot(scope: store.snapshotScope, syncedAt: date, assigned: edges, created: [], requested: []))
        await store.loadCachedSnapshot()
        #expect(store.assignedPulls == edges)
        #expect(store.isShowingCache)
        store.refresh(respectFreshness: true)
        #expect(store.isLoading)
        #expect(store.assignedPulls == edges)
        for _ in 0..<100 where store.isLoading { try await Task.sleep(for: .milliseconds(5)) }
        #expect(store.error != nil)
        #expect(store.lastSyncedAt == date)
        #expect(store.assignedPulls == edges)
    }

    @Test func cachingDoesNotChangeTheExistingCheckModePreferenceFormat() throws {
        #expect(BuildType.bridge.deserialize("commitStatus") == .commitStatus)
        #expect(BuildType.bridge.serialize(BuildType.none) == "none")
        let data = try JSONEncoder().encode(BuildType.commitStatus)
        #expect(try JSONDecoder().decode(BuildType.self, from: data) == .commitStatus)
    }

    @Test func freshnessHasAnExactDeadlineAndDoesNotTrustFutureDates() {
        let value = snapshot(scope: scope(), date: now)
        #expect(value.isFresh(at: now.addingTimeInterval(299), interval: 300))
        #expect(!value.isFresh(at: now.addingTimeInterval(300), interval: 300))
        #expect(!value.isFresh(at: now.addingTimeInterval(-1), interval: 300))
    }

    @Test @MainActor func cacheRestorationIsImmediateAndFreshnessOnlySkipsAutomaticRefresh() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PullSnapshotCache(directory: directory)
        let baseURL = GitHubSession.shared.cliConnection?.apiBaseURL ?? "https://api.github.com"
        let session = GitHubSession(connection: GitHubCLIConnection(executablePath: "/unused", username: "cache-user", apiBaseURL: baseURL))
        var calls = 0
        let store = PullRequestStore(startAutomatically: false, session: session, cache: cache, clientProvider: { _, _ in
            calls += 1
            throw URLError(.notConnectedToInternet)
        })
        let date = Date.now
        let edges = TimelinePreviewData.items(now: date).prefix(3).map { Edge(node: $0.pull) }
        await cache.save(PullSnapshot(scope: store.snapshotScope, syncedAt: date, assigned: edges, created: [], requested: []))
        await store.loadCachedSnapshot()
        #expect(store.lastSyncedAt == date)
        #expect(store.assignedPulls == edges)
        #expect(!store.isLoading)
        store.refresh(respectFreshness: true)
        #expect(calls == 0)
        store.refresh() // A user-requested refresh always reaches GitHub.
        for _ in 0..<100 where store.isLoading { try await Task.sleep(for: .milliseconds(5)) }
        #expect(calls == 1)
        #expect(store.error != nil)
        #expect(store.assignedPulls == edges)
        #expect(store.lastSyncedAt == date) // Failed refresh keeps the saved snapshot and its real age.
        store.clear()
        await store.loadCachedSnapshot()
        #expect(store.lastSyncedAt == nil)
    }
}
