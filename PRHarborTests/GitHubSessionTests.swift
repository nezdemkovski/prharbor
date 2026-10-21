import Foundation
import Defaults
import Testing
@testable import PRHarbor

@Suite("GitHub connection", .serialized)
@MainActor
struct GitHubSessionTests {
    private let connection = GitHubConnection(username: "octocat", apiBaseURL: "https://api.github.com")

    @Test func aDisconnectedOrDifferentHostCannotCreateAClient() async throws {
        let session = GitHubSession(connection: nil)
        await #expect(throws: GitHubAccessError.signInRequired) { try await session.client(baseURL: "https://api.github.com", buildType: .none) }
        try session.connect(connection, token: "token")
        await #expect(throws: GitHubAccessError.signInRequired) { try await session.client(baseURL: "https://other.example/api/v3", buildType: .none) }
        #expect(try await session.client(baseURL: "https://api.github.com", buildType: .none).expectedLogin == "octocat")
    }

    @Test func aSavedConnectionWithoutAStoredTokenAsksForOne() async {
        let session = GitHubSession(connection: connection)
        await #expect(throws: GitHubAccessError.signInRequired) { try await session.client(baseURL: "https://api.github.com", buildType: .none) }
    }

    @Test func tokensAreStoredPerHostAndRemovedOnDisconnect() throws {
        let tokens = GitHubTokenStorage.memory()
        var writes: [GitHubConnection?] = []
        let session = GitHubSession(connection: nil, tokens: tokens, persist: { writes.append($0) })
        try session.connect(connection, token: "secret")
        #expect(try tokens.read("https://api.github.com") == "secret")
        #expect(try tokens.read("https://github.example.com/api/v3") == nil)
        session.disconnect()
        #expect(try tokens.read("https://api.github.com") == nil)
        #expect(session.connection == nil)
        #expect(writes == [connection, nil])
    }
}
