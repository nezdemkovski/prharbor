import Foundation
import Defaults
import Testing
@testable import PRHarbor

@Suite("Isolated app test host", .serialized)
struct AppRuntimeTests {
    @Test @MainActor func startupUsesNoProductionAccountOrPreferences() {
        #expect(AppRuntime.isTesting)
        #expect(AppPreferences.storage !== UserDefaults.standard)
        #expect(Defaults.Keys.githubCLIConnection.suite === AppPreferences.storage)
        #expect(Defaults[.githubCLIConnection] == nil)
        #expect(Defaults[.githubUsername].isEmpty)
        #expect(!GitHubSession.shared.isConfigured)
        #expect(GitHubSession.shared.cleanupError == nil)
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

    @Test @MainActor func sandboxPreferencesMoveOnceWithoutOverwritingLaterChanges() throws {
        let suite = "prharbor-migration-test-" + UUID().uuidString
        let storage = try #require(UserDefaults(suiteName: suite))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".plist")
        defer {
            storage.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: file)
        }
        let values: [String: Any] = ["githubUsername": "octocat", "refreshRate": 10,
                                     "NSWindow Frame old": "old-frame", "directCLIPreferencesMigratedV1": false]
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        try data.write(to: file)
        storage.set(5, forKey: "refreshRate")
        AppPreferences.migrateSandboxPreferences(from: file, into: storage)
        #expect(storage.string(forKey: "githubUsername") == "octocat")
        #expect(storage.integer(forKey: "refreshRate") == 10)
        #expect(storage.object(forKey: "NSWindow Frame old") == nil)
        storage.set(15, forKey: "refreshRate")
        storage.removeObject(forKey: "githubUsername")
        AppPreferences.migrateSandboxPreferences(from: file, into: storage)
        #expect(storage.integer(forKey: "refreshRate") == 15)
        #expect(storage.persistentDomain(forName: suite)?["githubUsername"] == nil)
    }
}
