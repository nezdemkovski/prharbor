import Foundation

/// How this process was launched, decided once. Hosted tests run inside the app executable,
/// so the launch itself chooses inert services for them; components below never check.
nonisolated enum AppRuntime: Equatable, Sendable {
    case production
    /// Hosted unit tests: no account, notifications, status item or persistent data.
    case testHost
    /// Debug-only sample timeline, `PRHARBOR_PREVIEW=1`.
    case timelinePreview

    static let current: AppRuntime = {
        let environment = ProcessInfo.processInfo.environment
        if environment["PRHARBOR_TESTING"] == "1" || environment["XCTestConfigurationFilePath"] != nil { return .testHost }
        #if DEBUG
        if environment["PRHARBOR_PREVIEW"] == "1" { return .timelinePreview }
        #endif
        return .production
    }()

    /// Ordinary Debug runs behave like Release. Separate windows are opt-in tools.
    var showsDevelopmentWindow: Bool {
        #if DEBUG
        self == .timelinePreview || ProcessInfo.processInfo.environment["PRHARBOR_DEBUG_WINDOW"] == "1"
        #else
        false
        #endif
    }

    /// The sample account the preview's settings show instead of the connected one.
    @MainActor var usernameOverride: String? {
        #if DEBUG
        self == .timelinePreview ? TimelinePreviewData.username : nil
        #else
        nil
        #endif
    }
}

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

enum AppPreferences {
    // Preference keys are declared statically, so their suite is chosen here: production keeps
    // its existing domain; each test run gets an empty suite, independent of the signed-in account.
    static let storage: UserDefaults = AppRuntime.current == .testHost
        ? UserDefaults(suiteName: "com.nezdemkovski.prharbor.tests." + UUID().uuidString)!
        : .standard
}
