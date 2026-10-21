import Defaults
import LaunchAtLogin
import SwiftUI

struct GeneralSettings: View {
    @Default(.refreshRate) private var refresh
    @Default(.counterType) private var counter

    var body: some View {
        Form {
            Section("Startup") {
                LaunchAtLogin.Toggle("Open at login")
            }
            Section {
                Picker("Refresh every", selection: $refresh) {
                    ForEach([1, 5, 10, 15, 30], id: \.self) { Text("\($0) min").tag($0) }
                }
            } header: {
                Text("Sync")
            } footer: {
                Text("Opening the panel also refreshes when the last sync is older than this.")
            }
            Section("Menu bar") {
                Picker("Counter", selection: $counter) {
                    ForEach(CounterType.allCases) { Text($0.description).tag($0) }
                }
            }
        }
    }
}
