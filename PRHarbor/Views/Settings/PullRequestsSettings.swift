import Defaults
import SwiftUI

struct PullRequestsSettings: View {
    @Default(.showRequested) private var requested
    @Default(.showAssigned) private var assigned
    @Default(.showCreated) private var created
    @Default(.hideDrafts) private var hideDrafts
    @Default(.buildType) private var buildType
    @Default(.wakeOnComment) private var wake

    var body: some View {
        Form {
            Section("Show in the panel") {
                Toggle("Review requested", isOn: $requested)
                Toggle("Assigned to me", isOn: $assigned)
                Toggle("My pull requests", isOn: $created)
                Toggle("Hide drafts", isOn: $hideDrafts)
            }
            Section {
                Picker("CI status from", selection: $buildType) {
                    ForEach(BuildType.allCases) { Text($0.description).tag($0) }
                }
            } header: {
                Text("CI status")
            } footer: {
                Text("Which checks the panel reads for each pull request's latest commit.")
            }
            Section {
                Toggle("Wake up when someone comments", isOn: $wake)
            } header: {
                Text("Snooze")
            } footer: {
                Text("Snooze a pull request from its details until tomorrow, in 3 days or next week.")
            }
        }
    }
}
