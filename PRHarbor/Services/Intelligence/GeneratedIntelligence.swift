import Foundation
import FoundationModels
import NaturalLanguage

@Generable
nonisolated struct GeneratedSearchFilter {
    @Guide(description: "Individual search tokens for the request, using only the supplied syntax. Empty for unsupported requests.", .count(0...8))
    var filters: [String]
    @Guide(description: "True when the tokens express the whole request. False when any requested criterion is unsupported.")
    var supported: Bool
}

@Generable
nonisolated struct GeneratedMorningBrief {
    @Guide(description: "A single concise English sentence restating the supplied PR status facts. At most 180 characters. No advice, invented causes, or discussion content.")
    var explanation: String
}
