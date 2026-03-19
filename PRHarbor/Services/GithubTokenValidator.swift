
import SwiftUI
import Defaults

@MainActor
class GithubTokenValidator: ObservableObject {

    @Published var iconName: String = "clock.fill"
    @Published var iconColor: Color = Color(.systemGray)

    func setLoading() {
        self.iconName = "clock.fill"
        self.iconColor = Color(.systemGray)
    }

    func setInvalid() {
        self.iconName = "exclamationmark.circle.fill"
        self.iconColor = Color(.systemRed)
    }

    func setValid() {
        self.iconName = "checkmark.circle.fill"
        self.iconColor = Color(.systemGreen)
    }

    func validate() {
        setLoading()
        Task {
            do {
                let user = try await GitHubClient().fetchUser()
                Defaults[.githubUsername] = user.login
                setValid()
            } catch {
                setInvalid()
            }
        }
    }
}
