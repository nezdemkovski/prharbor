import Foundation

/// Test hosts use the app executable but must never start its production services.
nonisolated enum AppRuntime {
    static var isTesting: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["PRHARBOR_TESTING"] == "1" || environment["XCTestConfigurationFilePath"] != nil
    }
}

enum AppPreferences {
    // Production keeps its existing domain and preference keys. Each test run
    // gets an empty suite, independent of the developer's signed-in account.
    static let storage: UserDefaults = {
        if AppRuntime.isTesting {
            return UserDefaults(suiteName: "com.nezdemkovski.prharbor.tests." + UUID().uuidString)!
        }
        let storage = UserDefaults.standard
        // Preserve settings from the app's former sandbox domain, if readable.
        // No gh configuration or credentials are accessed by this migration.
        if let identifier = Bundle.main.bundleIdentifier {
            let previousFile = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/\(identifier)/Data/Library/Preferences/\(identifier).plist")
            migrateSandboxPreferences(from: previousFile, into: storage)
        }
        return storage
    }()

    static func migrateSandboxPreferences(from file: URL, into storage: UserDefaults) {
        let marker = "directCLIPreferencesMigratedV1"
        guard !storage.bool(forKey: marker),
              let data = try? Data(contentsOf: file),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return }
        for (key, value) in values where !key.hasPrefix("NS") && key != marker {
            storage.set(value, forKey: key)
        }
        storage.set(true, forKey: marker)
    }
}
