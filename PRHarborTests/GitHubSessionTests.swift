import Foundation
import Defaults
import SwiftUI
import Security
import ImageIO
import Testing
@testable import PRHarbor

@Suite("CLI connection", .serialized)
@MainActor
struct GitHubSessionTests {
    private let connection = GitHubCLIConnection(executablePath: "/opt/homebrew/bin/gh", username: "octocat", apiBaseURL: "https://api.github.com")

    @Test func aDisconnectedOrDifferentHostCannotCreateAClient() async {
        let session = GitHubSession(connection: nil)
        await #expect(throws: GitHubCLIError.self) { try await session.client(baseURL: "https://api.github.com", buildType: .none) }
        session.useCLI(connection)
        await #expect(throws: GitHubCLIError.self) { try await session.client(baseURL: "https://other.example/api/v3", buildType: .none) }
    }

    @Test func clientsVerifyTheConnectedAccountWithoutASeparateRequest() async throws {
        let fixture = try CLIExecutableFixture(response: Data(#"{"data":{"viewer":{"login":"octocat"},"search":{"edges":[],"issueCount":0,"pageInfo":{"hasNextPage":false,"endCursor":null}}}}"#.utf8))
        defer { fixture.remove() }
        let session = GitHubSession(connection: .init(executablePath: fixture.executable.path, username: "octocat", apiBaseURL: "https://api.github.com"))
        let client = try await session.client(baseURL: "https://api.github.com", buildType: .none)
        #expect(client.expectedLogin == "octocat")
        #expect(!FileManager.default.fileExists(atPath: fixture.arguments.path))
        #expect(try await client.fetchPulls(filter: "author:octocat").isEmpty)
        let arguments = try String(contentsOf: fixture.arguments, encoding: .utf8)
        #expect(arguments.hasPrefix("api\ngraphql\n"))
    }
}
