
import Foundation
import SwiftUI
import Defaults

@MainActor
final class GitHubDeviceFlowAuth: ObservableObject {

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
        pollTask?.cancel()
        pollTask = nil
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
        let url = try GitHubConstants.deviceCodeUrl(baseUrl: baseUrl)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            URLQueryItem(name: "client_id", value: GitHubConstants.oauthClientId),
            URLQueryItem(name: "scope", value: GitHubConstants.requiredScopes)
        ])

        let data = try await performRequest(request)
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

                    pollTask = nil
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
                    pollTask = nil
                    state = .error("Code expired. Please try again.")
                    return
                case "access_denied":
                    pollTask = nil
                    state = .error("Authorization denied.")
                    return
                default:
                    pollTask = nil
                    state = .error(response.errorDescription ?? "Unknown error")
                    return
                }
            } catch {
                if !Task.isCancelled {
                    pollTask = nil
                    state = .error(error.localizedDescription)
                }
                return
            }
        }
    }

    private func exchangeDeviceCode(deviceCode: String, baseUrl: String) async throws -> DeviceTokenResponse {
        let url = try GitHubConstants.tokenUrl(baseUrl: baseUrl)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            URLQueryItem(name: "client_id", value: GitHubConstants.oauthClientId),
            URLQueryItem(name: "device_code", value: deviceCode),
            URLQueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:device_code")
        ])

        let data = try await performRequest(request)
        return try JSONDecoder().decode(DeviceTokenResponse.self, from: data)
    }

    private func performRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return data
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(DeviceTokenResponse.self, from: data),
               let error = errorResponse.error {
                throw NSError(domain: "GitHubDeviceFlow", code: httpResponse.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: errorResponse.errorDescription ?? error
                ])
            }

            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let description: String
            if let message, !message.isEmpty {
                description = "HTTP \(httpResponse.statusCode): \(message)"
            } else {
                description = "HTTP \(httpResponse.statusCode)"
            }

            throw NSError(domain: "GitHubDeviceFlow", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: description
            ])
        }
    }

    private func formBody(_ items: [URLQueryItem]) -> Data? {
        var components = URLComponents()
        components.queryItems = items
        return components.percentEncodedQuery?.data(using: .utf8)
    }
}
