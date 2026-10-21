import Foundation

/// The services one launch uses, built by the app delegate.
@MainActor struct AppServices {
    let session: GitHubSession
    let cache: PullSnapshotCache
    let startsSync: Bool

    init(runtime: AppRuntime) {
        switch runtime {
        case .production:
            session = .live()
            cache = PullSnapshotCache(directory: PullSnapshotCache.productionDirectory)
            startsSync = true
        case .testHost, .timelinePreview:
            session = GitHubSession()
            cache = .temporary()
            startsSync = false
        }
    }
}
