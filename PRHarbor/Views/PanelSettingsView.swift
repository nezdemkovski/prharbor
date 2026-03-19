
import SwiftUI
import Defaults
import KeychainAccess
import LaunchAtLogin

struct PanelSettingsView: View {
    @ObservedObject var store: PullRequestStore

    @StateObject private var deviceFlowAuth = GitHubDeviceFlowAuth()
    @StateObject private var githubTokenValidator = GithubTokenValidator()

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                AccountCard(
                    store: store,
                    deviceFlowAuth: deviceFlowAuth,
                    githubTokenValidator: githubTokenValidator
                )
                VisibilityCard()
                AppearanceCard()
                MenubarCard()
                NotificationsCard()
                HiddenBranchesCard()
            }
            .padding(.horizontal, Theme.settingsPaddingH)
            .padding(.vertical, Theme.settingsPaddingV)
        }
        .onChange(of: deviceFlowAuth.state) { newState in
            if case .success = newState {
                store.refresh()
            }
        }
        .onChange(of: githubTokenValidator.iconName) { newName in
            if newName == "checkmark.circle.fill" {
                store.refresh()
            }
        }
    }
}
private struct AccountCard: View {
    @ObservedObject var store: PullRequestStore
    @ObservedObject var deviceFlowAuth: GitHubDeviceFlowAuth
    @ObservedObject var githubTokenValidator: GithubTokenValidator

    @Default(.githubApiBaseUrl) var githubApiBaseUrl
    @Default(.githubUsername) var githubUsername
    @FromKeychain(.githubToken) var githubToken

    private var isLoggedIn: Bool {
        !githubToken.isEmpty && !githubUsername.isEmpty
    }

    var body: some View {
        SettingsSection("ACCOUNT") {
            if isLoggedIn {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Theme.success)
                        .frame(width: 8, height: 8)
                    Text("@\(githubUsername)")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button {
                        githubToken = ""
                        githubUsername = ""
                        deviceFlowAuth.cancel()
                        store.clear()
                    } label: {
                        Text("Sign out")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                DeviceFlowSection(auth: deviceFlowAuth)

                SectionDivider()

                TokenSection(
                    githubApiBaseUrl: $githubApiBaseUrl,
                    githubToken: $githubToken,
                    validator: githubTokenValidator
                )
            }
        }
    }
}

private struct DeviceFlowSection: View {
    @ObservedObject var auth: GitHubDeviceFlowAuth

    var body: some View {
        switch auth.state {
        case .idle:
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    auth.startLogin()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "person.badge.key")
                        Text("Sign in with GitHub")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                SettingsHint("Quick OAuth login — some orgs may require admin approval")
            }

        case .waitingForUser(let userCode, _):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(userCode)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.groupedBackground, in: RoundedRectangle(cornerRadius: 6))
                    Text("Copied")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.success)
                }
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Waiting for authorization...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { auth.cancel() }
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }

        case .success:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
                Text("Connected")
                    .font(.system(size: 12, weight: .medium))
            }

        case .error(let message):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.failure)
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Button("Try again") { auth.startLogin() }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

private struct TokenSection: View {
    @Binding var githubApiBaseUrl: String
    @Binding var githubToken: String
    @ObservedObject var validator: GithubTokenValidator

    var body: some View {
        SettingsHint("Or use a Personal Access Token")

        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("API URL")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                TextField("https://api.github.com", text: $githubApiBaseUrl)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Token")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                SecureField("ghp_...", text: $githubToken)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit { validator.validate() }
            }

            HStack(spacing: 8) {
                Button {
                    validator.validate()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: validator.iconName)
                            .foregroundStyle(validator.iconColor)
                        Text("Login")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Text("[Get a token](https://github.com/settings/tokens/new?scopes=repo)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
private struct VisibilityCard: View {
    @Default(.showAssigned) var showAssigned
    @Default(.showCreated) var showCreated
    @Default(.showRequested) var showRequested
    @Default(.hideDrafts) var hideDrafts
    @Default(.showFeatures) var showFeatures

    var body: some View {
        SettingsSection("FILTERS") {
            SettingsHint("Which PR categories to show as tabs")
            SettingsToggle("Review requested", isOn: $showRequested)
            SettingsToggle("Assigned to me", isOn: $showAssigned)
            SettingsToggle("My PRs", isOn: $showCreated)
            SettingsToggle("Features", isOn: $showFeatures)
            SettingsHint("Group PRs into features and auto-detect by branch")
            SectionDivider()
            SettingsToggle("Hide drafts", isOn: $hideDrafts)
            SettingsHint("Filter out PRs marked as draft")
        }
    }
}
private struct HiddenBranchesCard: View {
    @Default(.hiddenAutoBranches) var hiddenBranches

    var body: some View {
        if !hiddenBranches.isEmpty {
            SettingsSection("HIDDEN BRANCHES") {
                SettingsHint("Auto-detected branches you've hidden")
                ForEach(hiddenBranches, id: \.self) { branch in
                    HStack(spacing: 6) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(branch)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                hiddenBranches.removeAll { $0 == branch }
                            }
                        } label: {
                            Text("Unhide")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
private struct AppearanceCard: View {
    @Default(.showAvatar) var showAvatar
    @Default(.showLabels) var showLabels
    @Default(.showUnreadDot) var showUnreadDot
    @Default(.showLinesChanged) var showLinesChanged
    @Default(.showApprovals) var showApprovals
    @Default(.clickOpensLink) var clickOpensLink
    @Default(.buildType) var buildType
    @Default(.staleDays) var staleDays
    @Default(.sortOrder) var sortOrder
    @Default(.groupByRepo) var groupByRepo

    var body: some View {
        SettingsSection("DISPLAY") {
            SettingsToggle("Avatars", isOn: $showAvatar)
            SettingsToggle("Labels", isOn: $showLabels)
            SettingsToggle("Lines changed", isOn: $showLinesChanged)
            SettingsHint("Show +/- line counts on each PR")
            SettingsToggle("Approvals", isOn: $showApprovals)
            SettingsHint("Show review count with checkmark icon")
            SettingsToggle("Unread dot", isOn: $showUnreadDot)
            SettingsHint("Blue dot on PRs you haven't viewed yet")
            SettingsToggle("Click opens browser", isOn: $clickOpensLink)
            SettingsHint("Open PR in browser instead of expanding details")

            SectionDivider()

            SettingsPicker("Sort by", selection: $sortOrder, width: 160) {
                ForEach(SortOrder.allCases) { Text($0.description) }
            }
            SettingsToggle("Group by repo", isOn: $groupByRepo)
            SettingsHint("Group PRs under repository headers")

            SectionDivider()

            SettingsPicker("CI source", selection: $buildType, width: 140) {
                ForEach(BuildType.allCases) { Text($0.description) }
            }
            SettingsHint("GitHub Actions, status checks, or hidden")
            SettingsPicker("Stale after", selection: $staleDays, width: 100) {
                Text("Off").tag(0)
                Text("3 days").tag(3)
                Text("7 days").tag(7)
                Text("14 days").tag(14)
                Text("30 days").tag(30)
            }
            SettingsHint("Mark PRs with no activity as stale")
        }
    }
}
private struct MenubarCard: View {
    @Default(.counterType) var counterType
    @Default(.refreshRate) var refreshRate

    var body: some View {
        SettingsSection("MENUBAR") {
            SettingsPicker("Counter", selection: $counterType, width: 150) {
                ForEach(CounterType.allCases) { Text($0.description) }
            }
            SettingsHint("Which PR count to show next to the icon")
            SettingsPicker("Refresh", selection: $refreshRate, width: 100) {
                Text("1 min").tag(1)
                Text("5 min").tag(5)
                Text("10 min").tag(10)
                Text("15 min").tag(15)
                Text("30 min").tag(30)
            }
            SettingsHint("How often to fetch new data from GitHub")
            LaunchAtLogin.Toggle {
                Text("Launch at login")
                    .font(.system(size: 11.5))
            }
        }
    }
}
private struct NotificationsCard: View {
    @Default(.notifyReviewRequested) var notifyReviewRequested
    @Default(.notifyAssigned) var notifyAssigned
    @Default(.notifyCreated) var notifyCreated

    var body: some View {
        SettingsSection("NOTIFICATIONS") {
            SettingsHint("Alert when new PRs appear")
            SettingsToggle("Review requested", isOn: $notifyReviewRequested)
            SettingsToggle("Assigned to me", isOn: $notifyAssigned)
            SettingsToggle("My PRs", isOn: $notifyCreated)
        }
    }
}
private struct SettingsSection<Content: View>: View {
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
