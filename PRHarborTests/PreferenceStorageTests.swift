import Defaults
import Foundation
import Testing
@testable import PRHarbor

@Suite("Preference storage", .serialized)
struct PreferenceStorageTests {
    @Test func mergedLayersStyleReadsTheIntegersEarlierVersionsStored() {
        defer { Defaults.reset(.mergedLayersStyle) }
        AppPreferences.storage.set(1, forKey: "mergedLayersStyle")
        #expect(Defaults[.mergedLayersStyle] == .numbers)
        Defaults[.mergedLayersStyle] = .hidden
        #expect(AppPreferences.storage.integer(forKey: "mergedLayersStyle") == 2)
    }

    @Test func unknownGitHubValuesDecodeAsUnknown() throws {
        let decoded = try JSONDecoder().decode([MergeableState].self, from: Data(#"["MERGEABLE","SOMETHING_NEW"]"#.utf8))
        #expect(decoded == [.mergeable, .unknown])
    }
}
