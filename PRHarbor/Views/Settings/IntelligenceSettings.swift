import Defaults
import SwiftUI

struct IntelligenceSettings: View {
    @Default(.intelligentSearch) private var search
    @Default(.intelligentMorningBrief) private var morning

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $search) {
                    Text("Natural language search")
                    Text("Type a phrase in the search field. Results update automatically; regular searches stay instant.")
                }
                Toggle(isOn: $morning) {
                    Text("Morning overview in the panel")
                    Text("Up to three pull requests that need you, with short explanations when expanded.")
                }
            } footer: {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(
                        "Uses Apple's on-device model. Both features are off by default and do not change regular search or the morning summary notification."
                    )
                    if let message = PRIntelligenceService.unavailableMessage { Text(message) }
                }
            }
        }
    }
}
