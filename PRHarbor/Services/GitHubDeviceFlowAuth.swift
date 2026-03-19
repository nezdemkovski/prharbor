
import Foundation
import SwiftUI
import Defaults

@MainActor
class GitHubDeviceFlowAuth: ObservableObject {

    enum AuthState: Equatable {
        case idle
        case waitingForUser(userCode: String, verificationUri: String)
        case success
        case error(String)
    }

    @Published var state: AuthState = .idle
    @FromKeychain(.githubToken) private var githubToken

    private var pollTask: Task<Void, Never>?

    func startLogin() {
        state = .idle
        let baseUrl = Defaults[.githubApiBaseUrl]

        Task {
            do {
                let deviceCode = try await requestDeviceCode(baseUrl: baseUrl)

                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(deviceCode.userCode, forType: .string)

                state = .waitingForUser(
                    userCode: deviceCode.userCode,
                    verificationUri: deviceCode.verificationUri
                )

                if let url = URL(string: deviceCode.verificationUri) {
                    NSWorkspace.shared.open(url)
                }

                pollTask = Task {
                    await pollForToken(
                        deviceCode: deviceCode.deviceCode,
                        interval: deviceCode.interval,
                        baseUrl: baseUrl
                    )
                }
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    func cancel() {
        pollTask?.cancel()
        pollTask = nil
        state = .idle
    }
    private func requestDeviceCode(baseUrl: String) async throws -> DeviceCodeResponse {
        let url = GitHubConstants.deviceCodeUrl(baseUrl: baseUrl)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "client_id=\(GitHubConstants.oauthClientId)&scope=\(GitHubConstants.requiredScopes)"
        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)

        if let errorResponse = try? JSONDecoder().decode(DeviceTokenResponse.self, from: data),
           let error = errorResponse.error {
            throw NSError(domain: "GitHubDeviceFlow", code: 0, userInfo: [
                NSLocalizedDescriptionKey: errorResponse.errorDescription ?? error
            ])
        }

        return try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
    }

    private func pollForToken(deviceCode: String, interval: Int, baseUrl: String) async {
        var currentInterval = interval

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(currentInterval))
            guard !Task.isCancelled else { return }

            do {
                let response = try await exchangeDeviceCode(deviceCode: deviceCode, baseUrl: baseUrl)

                if let token = response.accessToken {
                    self.githubToken = token

                    if let user = try? await GitHubClient().fetchUser() {
                        Defaults[.githubUsername] = user.login
                    }

                    state = .success
                    return
                }

                switch response.error {
                case "authorization_pending":
                    continue
                case "slow_down":
                    currentInterval += 5
                    continue
                case "expired_token":
                    state = .error("Code expired. Please try again.")
                    return
                case "access_denied":
                    state = .error("Authorization denied.")
                    return
                default:
                    state = .error(response.errorDescription ?? "Unknown error")
                    return
                }
            } catch {
                if !Task.isCancelled {
                    state = .error(error.localizedDescription)
                }
                return
            }
        }
    }

    private func exchangeDeviceCode(deviceCode: String, baseUrl: String) async throws -> DeviceTokenResponse {
        let url = GitHubConstants.tokenUrl(baseUrl: baseUrl)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "client_id=\(GitHubConstants.oauthClientId)&device_code=\(deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code"
        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(DeviceTokenResponse.self, from: data)
    }
}
