import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case pullRequests = "Pull Requests"
    case timeline = "Timeline"
    case bots = "Bots"
    case notifications = "Notifications"
    case intelligence = "Apple Intelligence"
    case account = "Account"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .pullRequests: "arrow.triangle.pull"
        case .timeline: "chart.bar.xaxis"
        case .bots: "gearshape.2"
        case .notifications: "bell.badge"
        case .intelligence: "apple.intelligence"
        case .account: "person.crop.circle"
        }
    }
}

/// A settings window laid out like System Settings: sections in a sidebar, each a grouped form.
struct SettingsView: View {
    let store: PullRequestStore
    var usernameOverride: String? = nil
    @State private var tab: SettingsTab?

    init(store: PullRequestStore, usernameOverride: String? = nil) {
        self.store = store
        self.usernameOverride = usernameOverride
        _tab = State(initialValue: store.isConfigured ? .general : .account)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $tab) { tab in
                Label(tab.rawValue, systemImage: tab.symbol)
            }
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(Layout.settingsSidebarWidth)
        } detail: {
            let tab = tab ?? .general
            pane(tab).navigationTitle(tab.rawValue)
        }
        .frame(minWidth: Layout.settingsMinSize.width, minHeight: Layout.settingsMinSize.height)
    }

    @ViewBuilder func pane(_ tab: SettingsTab) -> some View {
        Group {
            switch tab {
            case .general: GeneralSettings()
            case .pullRequests: PullRequestsSettings()
            case .timeline: TimelineSettings(store: store, usernameOverride: usernameOverride)
            case .bots: BotSettings()
            case .notifications: NotificationSettings()
            case .intelligence: IntelligenceSettings()
            case .account: AccountSettings(store: store, usernameOverride: usernameOverride)
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }
}
