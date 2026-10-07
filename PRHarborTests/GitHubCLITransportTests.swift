import Foundation
import Defaults
import SwiftUI
import Security
import ImageIO
import Testing
@testable import PRHarbor

@Suite("GitHub CLI transport")
struct GitHubCLITransportTests {
    @Test func cliExitCodeOneStillAllowsTheOlderSchemaFallback() async throws {
        let fixture = try CLIExecutableFixture(response: Data(#"{"data":{"search":{"edges":[],"issueCount":0,"pageInfo":{"hasNextPage":false,"endCursor":null}}}}"#.utf8), fallbackStacks: true)
        defer { fixture.remove() }
        let baseURL = "https://cli-fallback.example.com/api/v3"
        let cli = try GitHubCLI(executablePath: fixture.executable.path, apiBaseURL: baseURL)
        let client = try GitHubClient(baseURL: baseURL, buildType: .none, transport: cli)
        #expect(try await client.fetchPulls(filter: "author:octocat").isEmpty)
        let request = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.input)) as? [String: Any])
        let query = try #require(request["query"] as? String)
        #expect(!query.contains("stack {"))
    }

    @Test func userAndGraphQLRequestsUseCLIWithoutCopyingAToken() async throws {
        let fixture = try CLIExecutableFixture(response: Data(#"{"data":{"search":{"edges":[],"issueCount":0,"pageInfo":{"hasNextPage":false,"endCursor":null}}}}"#.utf8))
        defer { fixture.remove() }
        let cli = try GitHubCLI(executablePath: fixture.executable.path, apiBaseURL: "https://api.github.com")
        let client = try GitHubClient(baseURL: "https://api.github.com", buildType: .none, transport: cli)
        #expect(try await client.fetchUser().login == "octocat")
        #expect(try await client.fetchPulls(filter: "author:octocat").isEmpty)
        let arguments = try String(contentsOf: fixture.arguments, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(arguments == ["api", "graphql", "--hostname", "github.com", "--method", "POST", "--input", "-"])
        let request = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.input)) as? [String: Any])
        let variables = try #require(request["variables"] as? [String: Any])
        #expect(variables["query"] as? String == "is:open is:pr author:octocat archived:false")
        #expect(try String(contentsOf: fixture.environment, encoding: .utf8) == "1|absent|absent")
    }

    @Test func drainsLargeResponsesAndDoesNotExposeProviderErrors() async throws {
        let response = Data(String(repeating: "x", count: 400_000).utf8)
        let fixture = try CLIExecutableFixture(response: response, stderr: response)
        defer { fixture.remove() }
        let cli = try GitHubCLI(executablePath: fixture.executable.path, apiBaseURL: "https://api.github.com", timeout: 5)
        #expect(try await cli.api("graphql", body: Data("{}".utf8)) == response)
        let rejected = try CLIExecutableFixture(response: Data(), stderr: Data("private-token-provider-details".utf8), exitStatus: 1)
        defer { rejected.remove() }
        let failing = try GitHubCLI(executablePath: rejected.executable.path, apiBaseURL: "https://api.github.com")
        do {
            _ = try await failing.api("graphql", body: Data("{}".utf8))
            Issue.record("A failed CLI request must not succeed")
        } catch let error as GitHubCLIError {
            #expect(!error.localizedDescription.contains("private-token-provider-details"))
        }
    }

    @Test func timeoutStopsTheChildProcess() async throws {
        let fixture = try CLIExecutableFixture(response: Data(), wait: true)
        defer { fixture.remove() }
        let cli = try GitHubCLI(executablePath: fixture.executable.path, apiBaseURL: "https://api.github.com", timeout: 0.2)
        do {
            _ = try await cli.api("user")
            Issue.record("An unresponsive CLI must time out")
        } catch let error as GitHubCLIError {
            guard case .timedOut = error else { Issue.record("Expected a timeout"); return }
        }
    }

    @Test func cancellationStopsTheChildProcess() async throws {
        let fixture = try CLIExecutableFixture(response: Data(), wait: true)
        defer { fixture.remove() }
        let cli = try GitHubCLI(executablePath: fixture.executable.path, apiBaseURL: "https://api.github.com", timeout: 5)
        let request = Task { try await cli.api("user") }
        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: fixture.arguments.path) { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        request.cancel()
        await #expect(throws: CancellationError.self) { try await request.value }
    }

    @Test @MainActor func disconnectClearsOnlyTheLocalAccountSelection() async throws {
        var writes: [GitHubCLIConnection?] = []
        let session = GitHubSession(connection: nil, persist: { writes.append($0) })
        let connection = GitHubCLIConnection(executablePath: "/opt/homebrew/bin/gh", username: "octocat", apiBaseURL: "https://api.github.com")
        session.useCLI(connection)
        #expect(session.cliConnection == connection)
        session.disconnect()
        #expect(session.cliConnection == nil)
        #expect(writes == [connection, nil])
        await #expect(throws: GitHubCLIError.self) { try await session.client(baseURL: "https://api.github.com", buildType: .none) }
    }

    @Test @MainActor func changedCLIAccountRequiresAnExplicitReconnect() async throws {
        let fixture = try CLIExecutableFixture(response: Data())
        defer { fixture.remove() }
        let session = GitHubSession(connection: nil)
        session.useCLI(.init(executablePath: fixture.executable.path, username: "different-user", apiBaseURL: "https://api.github.com"))
        do {
            _ = try await session.client(baseURL: "https://api.github.com", buildType: .none)
            Issue.record("A changed account must require reconnecting")
        } catch let error as GitHubCLIError {
            guard case .accountChanged = error else { Issue.record("Expected an account change error"); return }
        }
    }

    @Test func enterpriseHostIsExplicitAndInvalidHostsAreRejected() throws {
        #expect(try GitHubCLI(executablePath: "/bin/sh", apiBaseURL: "https://github.example.com/api/v3").hostname == "github.example.com")
        #expect(throws: GitHubCLIError.self) { try GitHubCLI(executablePath: "/bin/sh", apiBaseURL: "https://github.com/other") }
        #expect(throws: GitHubCLIError.self) { try GitHubCLI(executablePath: "/missing/gh", apiBaseURL: "https://api.github.com") }
    }
}
