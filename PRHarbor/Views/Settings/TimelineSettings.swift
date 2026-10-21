import Defaults
import SwiftUI

struct TimelineSettings: View {
    let store: PullRequestStore
    let usernameOverride: String?
    @Default(.ownCommentsCount) private var comments
    @Default(.mergedLayersStyle) private var merged

    var body: some View {
        Form {
            Section {
                FreshnessSettings(store: store, usernameOverride: usernameOverride)
                Toggle(isOn: $comments) {
                    Text("My own comments count as activity")
                    Text("When off, only commits reset the quiet time on your pull requests.")
                }
            } header: {
                Text("Freshness")
            } footer: {
                Text("How long a pull request can sit quietly before it changes color. Drag the handles.")
            }
            Section("Stacks") {
                Picker(selection: $merged) {
                    Text("Count").tag(MergedLayersStyle.count)
                    Text("Numbers").tag(MergedLayersStyle.numbers)
                    Text("Hide").tag(MergedLayersStyle.hidden)
                } label: {
                    Text("Merged layers")
                    Text("Shown next to the branch at the bottom of a stack.")
                }
            }
        }
    }
}
