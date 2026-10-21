import Defaults
import SwiftUI

struct AccountSettings: View {
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
                Text(
                    "Use https://api.github.com for GitHub, or your Enterprise API URL ending in /api/v3. Set it before adding a token; changing it disconnects the account."
                )
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
                        if replacing {
                            Button("Cancel") {
                                replacing = false
                                token = ""
                            }
                        }
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
                Text(
                    session.isConfigured && !replacing
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
