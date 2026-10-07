
import SwiftUI
import Defaults
import LaunchAtLogin

enum SettingsDestination: String, CaseIterable, Identifiable {
    case pulls = "Pull requests", timeline = "Timeline", stacks = "Stacks", bots = "Bots", snooze = "Snooze", menubar = "Menu bar", notifications = "Notifications", intelligence = "Apple Intelligence", account = "Account"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .pulls: "arrow.triangle.pull"
        case .timeline: "chart.bar.xaxis"
        case .stacks: "square.3.layers.3d"
        case .bots: "gearshape.2"
        case .snooze: "moon.zzz"
        case .menubar: "menubar.rectangle"
        case .notifications: "bell.badge"
        case .intelligence: "sparkles"
        case .account: "person.crop.circle"
        }
    }
    var color: Color {
        switch self {
        case .pulls: TimelineStyle.color(0x3d82f6)
        case .timeline: Freshness.fresh.color
        case .stacks: TimelineStyle.color(0x8b5cf6)
        case .bots: TimelineStyle.color(0x64748b)
        case .snooze: TimelineStyle.color(0x0ea5e9)
        case .menubar: .secondary
        case .notifications: Freshness.rotting.color
        case .intelligence: TimelineStyle.accent
        case .account: .gray
        }
    }
}

extension SettingsDestination {
    var about: String {
        switch self {
        case .pulls: "Which pull requests show up and how they are ordered."
        case .timeline: "How the timeline colors and measures quiet time."
        case .stacks: "How stacked pull requests are drawn."
        case .bots: "Accounts that are treated as automation."
        case .snooze: "Putting pull requests away for a while."
        case .menubar: "What appears in your menu bar."
        case .notifications: "When PR Harbor gets your attention."
        case .intelligence: "Optional help with search and your morning overview."
        case .account: "Your connection to GitHub."
        }
    }
}

struct PanelSettingsView: View {
    @ObservedObject var store: PullRequestStore
    var usernameOverride: String? = nil
    @State private var destination: SettingsDestination? = GitHubSession.shared.isConfigured ? .timeline : .account
    @Default(.githubUsername) private var username

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    TimelineAvatar(person: User(login: usernameOverride ?? username), size: 28)
                    Text((usernameOverride ?? username).isEmpty ? "Not connected" : "@" + (usernameOverride ?? username)).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                }.padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 12)
                ForEach(SettingsDestination.allCases) { section in
                    Button { destination = section } label: {
                        HStack(spacing: 9) {
                            Image(systemName: section.symbol).font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white).frame(width: 20, height: 20)
                                .background(section.color, in: RoundedRectangle(cornerRadius: 5))
                            Text(section.rawValue).font(.system(size: 13))
                            Spacer(minLength: 0)
                        }.padding(.horizontal, 8).padding(.vertical, 6)
                            .foregroundStyle(destination == section ? .white : TimelineStyle.text)
                            .background(destination == section ? TimelineStyle.accent : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(destination == section ? [.isSelected] : [])
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 10).padding(.vertical, 12).frame(width: 196)
                .background(TimelineStyle.track)
                .overlay(alignment: .trailing) { Rectangle().fill(TimelineStyle.line).frame(width: 1) }
            VStack(alignment: .leading, spacing: 0) {
                Text((destination ?? .timeline).rawValue).font(.system(size: 18, weight: .semibold)).tracking(-0.18)
                Text((destination ?? .timeline).about).font(.system(size: 12.5)).foregroundStyle(TimelineStyle.muted).padding(.top, 2).padding(.bottom, 14)
                if destination == .account {
                    ScrollView {
                        AccountCard(store: store)
                        EnterpriseSettings()
                    }
                } else {
                    TimelineSettingsPane(destination: destination ?? .timeline, store: store, usernameOverride: usernameOverride)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.background(TimelineStyle.panel).foregroundStyle(TimelineStyle.text).tint(TimelineStyle.accent)
        .navigationTitle("Settings")
    }
}

private struct EnterpriseSettings: View {
    @Default(.githubApiBaseUrl) private var apiURL
    var body: some View {
        Form {
            TextField("GitHub API URL", text: $apiURL)
                .textFieldStyle(.roundedBorder)
            Text("Use https://api.github.com for GitHub, or your Enterprise API URL.").font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }
}

private struct AccountCard: View {
    @ObservedObject var store: PullRequestStore
    @ObservedObject private var session = GitHubSession.shared
    @StateObject private var connector = GitHubCLIConnector()

    var body: some View {
        SettingsSection("GITHUB CLI") {
            if session.isConfigured, let connection = session.cliConnection {
                HStack(spacing: 8) {
                    Image(systemName: "terminal").foregroundStyle(Theme.success)
                    Text("@" + connection.username).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("Reconnect", action: connector.connect)
                        .controlSize(.small).disabled(connector.isConnecting)
                    Button("Disconnect") {
                        connector.cancel()
                        session.disconnect()
                    }.controlSize(.small)
                }
                SettingsHint("Connected through GitHub CLI. Disconnecting PR Harbor keeps gh signed in.")
            } else {
                Text("Use the GitHub account already signed in with gh on this Mac.")
                    .font(.system(size: 12))
                Button(action: connector.connect) {
                    SwiftUI.Label("Connect GitHub CLI", systemImage: "terminal")
                }.buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(connector.isConnecting)
                SettingsHint("First time? Install GitHub CLI and sign in from Terminal:")
                Text("brew install gh\ngh auth login")
                    .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                SettingsHint("PR Harbor uses the access your CLI account already has.")
            }
            if connector.isConnecting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking GitHub CLI…").font(.system(size: 12))
                    Spacer()
                    Button("Cancel", action: connector.cancel).controlSize(.small)
                }
            }
            if let error = connector.error {
                Text(error).font(.system(size: 11)).foregroundStyle(Theme.failure)
            }
            if let error = session.cleanupError {
                Text(error).font(.system(size: 11)).foregroundStyle(Theme.failure)
                Button("Retry cleanup", action: session.cleanupLegacyCredentials).controlSize(.small)
            }
        }
        .onDisappear { connector.cancel() }
        .onChange(of: connector.successfulConnections) { _, _ in store.refresh() }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title)
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 6) {
                content
            }
            .padding(Theme.contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.cardBackground)
            )
        }
    }
}

private struct SettingsToggle: View {
    let label: String
    @Binding var isOn: Bool

    init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(label)
                .font(.system(size: 11.5))
        }
    }
}

private struct SettingsPicker<SelectionValue: Hashable, Content: View>: View {
    let label: String
    @Binding var selection: SelectionValue
    let width: CGFloat
    @ViewBuilder let content: Content

    init(_ label: String, selection: Binding<SelectionValue>, width: CGFloat, @ViewBuilder content: () -> Content) {
        self.label = label
        self._selection = selection
        self.width = width
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Spacer()
            Picker(label, selection: $selection) {
                content
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: width)
        }
    }
}

private struct SettingsHint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SectionDivider: View {
    var body: some View {
        Divider().opacity(0.5).padding(.vertical, 2)
    }
}
