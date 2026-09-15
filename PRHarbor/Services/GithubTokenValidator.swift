import Combine
import Defaults
import SwiftUI

@MainActor
final class GitHubTokenValidator: ObservableObject {
    @Published var iconName = "clock.fill"
    @Published var iconColor = Color(.systemGray)
    @FromKeychain(.githubToken) private var githubToken
    private var validationTask: Task<Void, Never>?
    private var validationGeneration = 0

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
        validationTask?.cancel()
        validationGeneration += 1
        let generation = validationGeneration
        let token = githubToken
        let baseURL = Defaults[.githubApiBaseUrl]
        let buildType = Defaults[.buildType]
        setLoading()

        validationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let client = try GitHubClient(
                    token: token,
                    baseURL: baseURL,
                    buildType: buildType
                )
                let user = try await client.fetchUser()
                try Task.checkCancellation()
                guard generation == validationGeneration else { return }
                Defaults[.githubUsername] = user.login
                validationTask = nil
                setValid()
            } catch is CancellationError {
                return
            } catch {
                guard generation == validationGeneration, !Task.isCancelled else { return }
                validationTask = nil
                setInvalid()
            }
        }
    }
}
