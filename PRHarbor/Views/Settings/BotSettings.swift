import Defaults
import SwiftUI

struct BotSettings: View {
    @Default(.botAccounts) private var bots
    @State private var login = ""

    var body: some View {
        Form {
            Section {
                ForEach(bots, id: \.self) { bot in
                    LabeledContent {
                        Button("Remove", systemImage: "minus.circle") { bots.removeAll { $0 == bot } }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).help("Remove \(bot)")
                    } label: {
                        Text(bot).monospaced()
                    }
                }
                TextField("Add account", text: $login, prompt: Text("snyk-bot or *-ci"))
                    .monospaced()
                    .onSubmit(add)
            } header: {
                Text("Bot accounts")
            } footer: {
                Text("Their pull requests are grouped under Bots, and they don't count as reviewers. Use * as a wildcard; press Return to add.")
            }
            Section {
                Button("Reset to Defaults") { bots = Defaults.Keys.botAccounts.defaultValue }
            }
        }
    }

    private func add() {
        let value = login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if !bots.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) { bots.append(value) }
        login = ""
    }
}
