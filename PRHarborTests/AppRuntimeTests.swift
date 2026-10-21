import Foundation
import Defaults
import Testing
@testable import PRHarbor

@Suite("Isolated app test host", .serialized)
struct AppRuntimeTests {
    @Test @MainActor func startupUsesNoProductionAccountOrPreferences() {
        #expect(AppRuntime.current == .testHost)
        #expect(AppPreferences.storage !== UserDefaults.standard)
        #expect(Defaults.Keys.githubConnection.suite === AppPreferences.storage)
        #expect(Defaults[.githubConnection] == nil)
        let delegate = AppDelegate()
        #expect(!delegate.store.isConfigured)
        #expect(!delegate.store.isLoading)
        #expect(delegate.store.isEmpty)
    }

    @Test @MainActor func defaultCacheIsOutsideTheProductionCacheDirectory() {
        let production = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PRHarbor/Pulls", isDirectory: true)
        let cache = AppServices(runtime: AppRuntime.current).cache
        #expect(cache.directory != production)
        #expect(cache.directory.lastPathComponent.hasPrefix("PRHarbor-TestCache-"))
        #expect(PullSnapshotCache.productionDirectory == production)
    }
}
