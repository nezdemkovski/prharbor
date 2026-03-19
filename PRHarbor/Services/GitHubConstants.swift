
import Foundation

enum GitHubConstants {
    static let oauthClientId = "Ov23liiDmV3FId8NdEDo"
    static let requiredScopes = "repo"

    static func deviceCodeUrl(baseUrl: String) -> URL {
        let host = gitHubHost(from: baseUrl)
        return URL(string: "\(host)/login/device/code")!
    }

    static func tokenUrl(baseUrl: String) -> URL {
        let host = gitHubHost(from: baseUrl)
        return URL(string: "\(host)/login/oauth/access_token")!
    }

    private static func gitHubHost(from apiBaseUrl: String) -> String {
        if apiBaseUrl.contains("api.github.com") {
            return "https://github.com"
        }
        return apiBaseUrl.replacingOccurrences(of: "/api/v3", with: "")
    }
}
