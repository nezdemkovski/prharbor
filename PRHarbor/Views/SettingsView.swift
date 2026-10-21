import SwiftUI
import Defaults
import LaunchAtLogin
import UserNotifications

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General", pullRequests = "Pull Requests", timeline = "Timeline", bots = "Bots"
    case notifications = "Notifications", intelligence = "Apple Intelligence", account = "Account"
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

private struct GeneralSettings: View {
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

private struct PullRequestsSettings: View {
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

private struct TimelineSettings: View {
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
                    Text("Count").tag(0)
                    Text("Numbers").tag(1)
                    Text("Hide").tag(2)
                } label: {
                    Text("Merged layers")
                    Text("Shown next to the branch at the bottom of a stack.")
                }
            }
        }
    }
}

private struct BotSettings: View {
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

private struct NotificationSettings: View {
    @Default(.notifyReviewRequested) private var review
    @Default(.notifyAssigned) private var assigned
    @Default(.notifyCreated) private var created
    @Default(.notifyRotting) private var rotting
    @Default(.morningSummary) private var morning
    @Default(.morningSummaryMinutes) private var minutes
    @State private var permission = NotificationPermission()
    private var time: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            minutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
        })
    }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    switch permission.status {
                    case .notDetermined: Button("Allow…") { Task { await permission.request() } }
                    case .denied: Button("Open System Settings") { permission.openSystemSettings() }
                    case .authorized, .provisional: Button("Send Test") { permission.sendTest() }
                    default: EmptyView()
                    }
                } label: {
                    Text("Notifications")
                    Text(permissionHint)
                }
            }
            Section("Notify me when") {
                Toggle("Someone requests your review", isOn: $review)
                Toggle("You are assigned", isOn: $assigned)
                Toggle("A new pull request of yours appears", isOn: $created)
                Toggle("One of yours starts rotting", isOn: $rotting)
            }
            Section {
                Toggle("Morning summary notification", isOn: $morning)
                if morning {
                    DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Daily summary")
            } footer: {
                Text("How many pull requests wait for your review and how many of yours are rotting. Notifications appear while PR Harbor is running.")
            }
        }
        .task { await permission.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await permission.refresh() }
        }
    }

    private var permissionHint: String {
        switch permission.status {
        case .notDetermined: "PR Harbor has not asked yet."
        case .denied: "Turned off in System Settings. PR Harbor cannot show any notification."
        case .authorized, .provisional: "Allowed."
        default: "Checking…"
        }
    }
}

private struct IntelligenceSettings: View {
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
                    Text("Uses Apple's on-device model. Both features are off by default and do not change regular search or the morning summary notification.")
                    if let message = PRIntelligenceService.unavailableMessage { Text(message) }
                }
            }
        }
    }
}

private struct AccountSettings: View {
    let store: PullRequestStore
    let usernameOverride: String?
    @Default(.githubApiBaseUrl) private var apiURL
    @State private var connector: GitHubTokenConnector
    @State private var token = ""
    @State private var replacing = false
    @Environment(\.openURL) private var openURL
    private var session: GitHubSession { store.session }

    init(store: PullRequestStore, usernameOverride: String?) {
        self.store = store
        self.usernameOverride = usernameOverride
        _connector = State(initialValue: GitHubTokenConnector(session: store.session))
    }

    var body: some View {
        Form {
            Section {
                TextField("API URL", text: $apiURL)
            } header: {
                Text("Server")
            } footer: {
                Text("Use https://api.github.com for GitHub, or your Enterprise API URL ending in /api/v3. Set it before adding a token; changing it disconnects the account.")
            }
            Section {
                if let username = usernameOverride ?? (session.isConfigured ? session.connection?.username : nil), !replacing {
                    LabeledContent("Signed in as") {
                        HStack(spacing: Spacing.s) {
                            TimelineAvatar(person: User(login: username), size: Size.avatarSmall)
                            Text("@" + username)
                        }
                    }
                    HStack {
                        Spacer()
                        Button("Replace Token…") { replacing = true }
                        Button("Disconnect") {
                            connector.cancel()
                            session.disconnect()
                        }
                    }
                } else {
                    LabeledContent {
                        if let url = GitHubHTTPTransport.newTokenURL(apiBaseURL: apiURL) {
                            Button("Create Token on GitHub…") { openURL(url) }.help(url.absoluteString)
                        }
                    } label: {
                        Text("Personal access token")
                        Text("A classic token with the repo and read:org scopes, which the link preselects.")
                    }
                    SecureField("Token", text: $token, prompt: Text("ghp_…"))
                        .onSubmit { connector.connect(token: token) }
                    HStack {
                        if connector.isConnecting {
                            ProgressView().controlSize(.small)
                            Text("Checking token…").foregroundStyle(.secondary)
                        }
                        Spacer()
                        if replacing { Button("Cancel") { replacing = false; token = "" } }
                        Button("Connect") { connector.connect(token: token) }
                            .keyboardShortcut(.defaultAction)
                            .disabled(connector.isConnecting || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if let error = connector.error {
                    Text(error).foregroundStyle(.red)
                }
            } header: {
                Text("GitHub")
            } footer: {
                Text(session.isConfigured && !replacing
                    ? "The token is stored in your Keychain."
                    : "For organizations with SAML single sign-on, choose Configure SSO next to the token on GitHub and authorize it.")
            }
        }
        .onDisappear { connector.cancel() }
        .onChange(of: connector.successfulConnections) { _, _ in
            token = ""
            replacing = false
            store.refresh()
        }
    }
}
