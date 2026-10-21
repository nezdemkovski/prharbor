import Defaults
import Foundation
import Observation

/// Validates a pasted token, then stores it and selects its account.
@MainActor @Observable
final class GitHubTokenConnector {
    private(set) var isConnecting = false
    private(set) var error: String?
    private(set) var successfulConnections = 0
    private let session: GitHubSession
    private var task: Task<Void, Never>?
    private var generation = 0

    init(session: GitHubSession) { self.session = session }

    func connect(token: String) {
        cancel()
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        let epoch = generation
        let sessionEpoch = session.generation
        let baseURL = Defaults[.githubApiBaseUrl]
        isConnecting = true
        error = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let account = try await GitHubHTTPTransport(apiBaseURL: baseURL, token: token).account()
                try Task.checkCancellation()
                guard generation == epoch, session.generation == sessionEpoch,
                      Defaults[.githubApiBaseUrl] == baseURL, !account.user.login.isEmpty else { throw CancellationError() }
                if let scopes = account.scopes, !scopes.contains("repo") { throw GitHubAccessError.missingRepoScope }
                try session.connect(.init(username: account.user.login, apiBaseURL: baseURL), token: token)
                successfulConnections += 1
                isConnecting = false
                task = nil
            } catch is CancellationError {
                if generation == epoch { isConnecting = false; task = nil }
            } catch {
                guard generation == epoch, !Task.isCancelled else { return }
                self.error = error.localizedDescription
                isConnecting = false
                task = nil
            }
        }
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        isConnecting = false
    }
}
