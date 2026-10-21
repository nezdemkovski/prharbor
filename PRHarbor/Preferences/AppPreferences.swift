import Foundation

enum AppPreferences {
    // Preference keys are declared statically, so their suite is chosen here: production keeps
    // its existing domain; each test run gets an empty suite, independent of the signed-in account.
    static let storage: UserDefaults = AppRuntime.current == .testHost
        ? UserDefaults(suiteName: "com.nezdemkovski.prharbor.tests." + UUID().uuidString)!
        : .standard
}
