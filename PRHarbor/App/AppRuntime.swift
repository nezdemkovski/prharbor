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
        return UserDefaults.standard
    }()
}
