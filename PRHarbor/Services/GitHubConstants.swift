
import Foundation

enum GitHubConstants {
    static let oauthClientId = "Ov23liiDmV3FId8NdEDo"
    static let requiredScopes = "repo"

    static func deviceCodeUrl(baseUrl: String) throws -> URL {
        let host = gitHubHost(from: baseUrl)
        guard let url = URL(string: "\(host)/login/device/code") else {
            throw URLError(.badURL, userInfo: [
                NSLocalizedDescriptionKey: "Invalid GitHub device code URL."
            ])
        }
        return url
    }

    static func tokenUrl(baseUrl: String) throws -> URL {
        let host = gitHubHost(from: baseUrl)
        guard let url = URL(string: "\(host)/login/oauth/access_token") else {
            throw URLError(.badURL, userInfo: [
                NSLocalizedDescriptionKey: "Invalid GitHub token URL."
            ])
        }
        return url
    }

    private static func gitHubHost(from apiBaseUrl: String) -> String {
        if apiBaseUrl.contains("api.github.com") {
            return "https://github.com"
        }
        return apiBaseUrl.replacingOccurrences(of: "/api/v3", with: "")
    }
}
