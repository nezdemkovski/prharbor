import Defaults
import Foundation
import Observation
import Testing

@testable import PRHarbor

@Suite("GitHub connection", .serialized)
@MainActor
struct GitHubSessionTests {
    private let connection = GitHubConnection(username: "octocat", apiBaseURL: "https://api.github.com")

    @Test func aDisconnectedOrDifferentHostCannotCreateAClient() async throws {
        let session = GitHubSession(connection: nil)
        await #expect(throws: GitHubAccessError.signInRequired) {
            try await session.client(baseURL: "https://api.github.com", buildType: .none)
        }
        try session.connect(connection, token: "token")
        await #expect(throws: GitHubAccessError.signInRequired) {
            try await session.client(baseURL: "https://other.example/api/v3", buildType: .none)
        }
        #expect(try await session.client(baseURL: "https://api.github.com", buildType: .none).expectedLogin == "octocat")
    }

    @Test func aSavedConnectionWithoutAStoredTokenAsksForOne() async {
        let session = GitHubSession(connection: connection)
        await #expect(throws: GitHubAccessError.signInRequired) {
            try await session.client(baseURL: "https://api.github.com", buildType: .none)
        }
    }

    @Test func connectingIsVisibleToViewsThatOnlyObserveTheStore() throws {
        let session = GitHubSession(connection: nil)
        let store = PullRequestStore(startAutomatically: false, session: session)
        let changed = ObservationFlag()
        withObservationTracking {
            _ = store.isConfigured
        } onChange: {
            changed.set()
        }
        try session.connect(GitHubConnection(username: "octocat", apiBaseURL: Defaults[.githubApiBaseUrl]), token: "token")
        #expect(changed.value)
        #expect(store.isConfigured)
    }

    @Test func aSavedTokenRestoresTheAccountAfterPreferencesWereReset() async throws {
        let tokens = GitHubTokenStorage.memory()
        try tokens.save("saved", "https://api.github.com")
        let session = GitHubSession(connection: nil, tokens: tokens)
        await session.restoreFromSavedToken(baseURL: "https://api.github.com") { token in
            #expect(token == "saved")
            return "octocat"
        }
        #expect(session.connection == connection)
        // Without a token for the host, or once connected, nothing is requested.
        let empty = GitHubSession(connection: nil)
        await empty.restoreFromSavedToken(baseURL: "https://api.github.com") { _ in
            Issue.record("No token to verify")
            return ""
        }
        #expect(empty.connection == nil)
        await session.restoreFromSavedToken(baseURL: "https://api.github.com") { _ in
            Issue.record("Already connected")
            return ""
        }
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

private nonisolated final class ObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.withLock { flag = true } }
    var value: Bool { lock.withLock { flag } }
}
