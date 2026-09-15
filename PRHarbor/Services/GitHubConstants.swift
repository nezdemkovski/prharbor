
import Foundation

enum GitHubConstants {
    static let oauthClientId = "Ov23liiDmV3FId8NdEDo"
    static let requiredScopes = "repo"

    static func deviceCodeUrl(baseUrl: String) throws -> URL {
        try gitHubWebURL(from: baseUrl).appending(path: "login/device/code")
    }

    static func tokenUrl(baseUrl: String) throws -> URL {
        try gitHubWebURL(from: baseUrl).appending(path: "login/oauth/access_token")
    }

    private static func gitHubWebURL(from apiBaseUrl: String) throws -> URL {
        guard var components = URLComponents(string: apiBaseUrl),
              components.scheme == "https",
              let host = components.host,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw URLError(.badURL)
        }

        if host == "api.github.com" {
            guard let url = URL(string: "https://github.com") else {
                throw URLError(.badURL)
            }
            return url
        }

        var path = components.path
        if path.hasSuffix("/") {
            path.removeLast()
        }
        guard path.hasSuffix("/api/v3") else {
            throw URLError(.badURL, userInfo: [
                NSLocalizedDescriptionKey: "GitHub Enterprise API URL must end in /api/v3."
            ])
        }
        path.removeLast("/api/v3".count)
        components.path = path

        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }
}
