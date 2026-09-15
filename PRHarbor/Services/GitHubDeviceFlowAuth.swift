
import Combine
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

    private var authTask: Task<Void, Never>?
    private var authGeneration = 0

    func startLogin() {
        authTask?.cancel()
        authGeneration += 1
        let generation = authGeneration
        state = .idle
        let baseUrl = Defaults[.githubApiBaseUrl]

        authTask = Task { [weak self] in
            guard let self else { return }
            do {
                let deviceCode = try await requestDeviceCode(baseUrl: baseUrl)
                try Task.checkCancellation()
                guard generation == authGeneration else { return }

                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(deviceCode.userCode, forType: .string)

                state = .waitingForUser(
                    userCode: deviceCode.userCode,
                    verificationUri: deviceCode.verificationUri
                )

                if let url = URL(string: deviceCode.verificationUri) {
                    NSWorkspace.shared.open(url)
                }

                await pollForToken(
                    deviceCode: deviceCode.deviceCode,
                    interval: deviceCode.interval,
                    baseUrl: baseUrl,
                    generation: generation
                )
            } catch is CancellationError {
                return
            } catch {
                guard generation == authGeneration, !Task.isCancelled else { return }
                authTask = nil
                state = .error(error.localizedDescription)
            }
        }
    }

    func cancel() {
        authGeneration += 1
        authTask?.cancel()
        authTask = nil
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

    private func pollForToken(
        deviceCode: String,
        interval: Int,
        baseUrl: String,
        generation: Int
    ) async {
        var currentInterval = interval

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(currentInterval))
            guard !Task.isCancelled, generation == authGeneration else { return }

            do {
                let response = try await exchangeDeviceCode(deviceCode: deviceCode, baseUrl: baseUrl)

                if let token = response.accessToken {
                    let client = try GitHubClient(
                        token: token,
                        baseURL: baseUrl,
                        buildType: Defaults[.buildType]
                    )
                    let user = try await client.fetchUser()
                    try Task.checkCancellation()
                    guard generation == authGeneration else { return }

                    githubToken = token
                    Defaults[.githubUsername] = user.login
                    authTask = nil
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
                    authTask = nil
                    state = .error("Code expired. Please try again.")
                    return
                case "access_denied":
                    authTask = nil
                    state = .error("Authorization denied.")
                    return
                default:
                    authTask = nil
                    state = .error(response.errorDescription ?? "Unknown error")
                    return
                }
            } catch {
                if !Task.isCancelled {
                    authTask = nil
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
