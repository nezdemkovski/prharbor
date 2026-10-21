import Foundation
import Defaults
import Testing
@testable import PRHarbor

@Suite("Isolated app test host", .serialized)
struct AppRuntimeTests {
    @Test @MainActor func startupUsesNoProductionAccountOrPreferences() {
        #expect(AppRuntime.isTesting)
        #expect(AppPreferences.storage !== UserDefaults.standard)
        #expect(Defaults.Keys.githubConnection.suite === AppPreferences.storage)
        #expect(Defaults[.githubConnection] == nil)
        #expect(Defaults[.githubUsername].isEmpty)
        #expect(!GitHubSession.shared.isConfigured)
        let delegate = AppDelegate()
        #expect(!delegate.store.isLoading)
        #expect(delegate.store.isEmpty)
    }

    @Test func defaultCacheIsOutsideTheProductionCacheDirectory() {
        let production = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PRHarbor/Pulls", isDirectory: true)
        #expect(PullSnapshotCache.defaultDirectory != production)
        #expect(PullSnapshotCache.defaultDirectory.lastPathComponent.hasPrefix("PRHarbor-TestCache-"))
    }
}
