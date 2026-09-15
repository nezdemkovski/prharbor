import Combine
import Defaults
import SwiftUI

@MainActor
final class GitHubTokenValidator: ObservableObject {
    @Published var iconName = "clock.fill"
    @Published var iconColor = Color(.systemGray)
    @FromKeychain(.githubToken) private var githubToken

    func setLoading() {
        iconName = "clock.fill"
        iconColor = Color(.systemGray)
    }

    func setInvalid() {
        iconName = "exclamationmark.circle.fill"
        iconColor = Color(.systemRed)
    }

    func setValid() {
        iconName = "checkmark.circle.fill"
        iconColor = Color(.systemGreen)
    }

    func validate() {
        setLoading()
        Task {
            do {
                let client = try GitHubClient(
                    token: githubToken,
                    baseURL: Defaults[.githubApiBaseUrl],
                    buildType: Defaults[.buildType]
                )
                let user = try await client.fetchUser()
                Defaults[.githubUsername] = user.login
                setValid()
            } catch {
                setInvalid()
            }
        }
    }
}
