import Foundation

/// Orders the store's cache work: a load waits for pending removals, and writes and removals
/// run one after another, so an older snapshot can never land after a newer one or a clear.
@MainActor
final class SnapshotStorage {
    private let cache: PullSnapshotCache
    private var writeTask: Task<Void, Never>?
    private var removalTask: Task<Void, Never>?

    init(cache: PullSnapshotCache) {
        self.cache = cache
    }

    func load(scope: PullSnapshotScope) async -> PullSnapshot? {
        await removalTask?.value
        return await cache.load(scope: scope)
    }

    @discardableResult
    func save(_ snapshot: PullSnapshot) -> Task<Void, Never> {
        let cache = cache, previousWrite = writeTask, previousRemoval = removalTask
        let task = Task {
            await previousWrite?.value
            await previousRemoval?.value
            guard !Task.isCancelled else { return }
            await cache.save(snapshot)
        }
        writeTask = task
        return task
    }

    /// Cancels unfinished writes and removes the snapshot for `scope`.
    func remove(scope: PullSnapshotScope) {
        writeTask?.cancel()
        let cache = cache, previousWrite = writeTask, previousRemoval = removalTask
        removalTask = Task {
            await previousWrite?.value
            await previousRemoval?.value
            await cache.remove(scope: scope)
        }
    }
}
