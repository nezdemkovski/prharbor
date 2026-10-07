import Foundation

/// Everything affecting the fetched snapshot, including its selected CLI identity.
nonisolated struct PullSnapshotScope: Codable, Equatable, Sendable {
    let username: String
    let baseURL: String
    let buildType: BuildType
    let hideDrafts: Bool
    let assigned: Bool
    let created: Bool
    let requested: Bool
}

nonisolated struct PullSnapshot: Codable, Sendable {
    var version = 1
    var isComplete = true
    let scope: PullSnapshotScope
    let syncedAt: Date
    let assigned: [Edge]
    let created: [Edge]
    let requested: [Edge]

    func isFresh(at now: Date, interval: TimeInterval) -> Bool {
        let age = now.timeIntervalSince(syncedAt)
        return isComplete && age >= 0 && age < interval
    }
}

/// Disk work and JSON coding run on this actor, never on the UI executor.
/// One bounded file in the app's cache directory; no credentials and no shared gh cache.
actor PullSnapshotCache {
    static let defaultDirectory = AppRuntime.isTesting
        ? FileManager.default.temporaryDirectory.appendingPathComponent("PRHarbor-TestCache-" + UUID().uuidString, isDirectory: true)
        : FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PRHarbor/Pulls", isDirectory: true)
    static let shared = PullSnapshotCache(directory: defaultDirectory)
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("snapshot-v1.json") }
    private let maximumBytes = 8 * 1_024 * 1_024
    private let maximumAge: TimeInterval = 7 * 86_400

    init(directory: URL) { self.directory = directory }

    func load(scope: PullSnapshotScope, now: Date = .now) -> PullSnapshot? {
        do {
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= maximumBytes else { return nil }
            let snapshot = try JSONDecoder().decode(PullSnapshot.self, from: Data(contentsOf: file))
            let age = now.timeIntervalSince(snapshot.syncedAt)
            guard snapshot.version == 1, snapshot.scope == scope, age >= 0, age <= maximumAge else { return nil }
            return snapshot
        } catch { return nil } // A missing/corrupt/evicted cache simply needs a live fetch.
    }

    func save(_ snapshot: PullSnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            guard data.count <= maximumBytes else { return }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch { /* Caching is optional; never hide successful live data on disk failure. */ }
    }

    func remove(scope: PullSnapshotScope) {
        guard let snapshot = try? JSONDecoder().decode(PullSnapshot.self, from: Data(contentsOf: file)),
              snapshot.scope.username == scope.username, snapshot.scope.baseURL == scope.baseURL else { return }
        try? FileManager.default.removeItem(at: file)
    }
}
