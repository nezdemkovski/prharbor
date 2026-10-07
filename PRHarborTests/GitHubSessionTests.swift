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

    @Test func migrationPreservesOnlyAnActiveCLIConnection() {
        #expect(GitHubSession.migratedConnection(connection, legacyMethod: "cli") == connection)
        #expect(GitHubSession.migratedConnection(connection, legacyMethod: nil) == connection)
        #expect(GitHubSession.migratedConnection(connection, legacyMethod: "token") == nil)
        #expect(GitHubSession.migratedConnection(connection, legacyMethod: "disconnected") == nil)
        #expect(GitHubSession.migratedConnection(nil, legacyMethod: "cli") == nil)
    }

    @Test func bridgeMigrationPreservesIdentityAndNeverExecutesTheScript() throws {
        let old = GitHubCLIConnection(executablePath: "/Users/example/Library/Application Scripts/com.nezdemkovski.prharbor/prharbor-gh",
                                      username: connection.username, apiBaseURL: connection.apiBaseURL)
        let migrated = GitHubSession.migratedConnection(old, legacyMethod: nil, findExecutable: { "/opt/homebrew/bin/gh" })
        #expect(migrated == connection)
        #expect(try GitHubCLI.resolvedExecutablePath(old.executablePath, findExecutable: { "/opt/homebrew/bin/gh" }) == connection.executablePath)
        #expect(GitHubSession.migratedConnection(old, legacyMethod: nil, findExecutable: { throw GitHubCLIError.notInstalled }) == old)
        #expect(throws: GitHubCLIError.self) {
            try GitHubCLI.resolvedExecutablePath(old.executablePath, findExecutable: { throw GitHubCLIError.notInstalled })
        }
        #expect(GitHubSession.migratedConnection(connection, legacyMethod: nil, findExecutable: {
            Issue.record("An existing direct executable must be preserved")
            return "/unexpected/gh"
        }) == connection)
    }

    @Test func legacyCleanupIsScopedToTheAppsOwnTwoEntries() {
        let queries = LegacyGitHubCredentialCleanup.queries()
        #expect(queries.count == 2)
        #expect(Set(queries.compactMap { $0[kSecAttrAccount as String] as? String }) == ["githubToken", "githubSession"])
        #expect(queries.allSatisfy { ($0[kSecAttrService as String] as? String) == "com.nezdemkovski.prharbor" })
        #expect(queries.allSatisfy { ($0[kSecClass as String] as? String) == (kSecClassGenericPassword as String) })
        #expect(queries.allSatisfy { $0[kSecReturnData as String] == nil && $0[kSecValueData as String] == nil })
    }

    @Test func aDisconnectedOrDifferentHostCannotCreateAClient() async {
        let session = GitHubSession(connection: nil)
        await #expect(throws: GitHubCLIError.self) { try await session.client(baseURL: "https://api.github.com", buildType: .none) }
        session.useCLI(connection)
        await #expect(throws: GitHubCLIError.self) { try await session.client(baseURL: "https://other.example/api/v3", buildType: .none) }
    }

    @Test func disconnectInvalidatesAnAccountCheckAlreadyInFlight() async throws {
        let fixture = try CLIExecutableFixture(response: Data(), delay: 0.15)
        defer { fixture.remove() }
        let session = GitHubSession(connection: .init(executablePath: fixture.executable.path, username: "octocat", apiBaseURL: "https://api.github.com"))
        let pending = Task { try await session.client(baseURL: "https://api.github.com", buildType: .none) }
        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: fixture.arguments.path) { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(FileManager.default.fileExists(atPath: fixture.arguments.path))
        session.disconnect()
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(session.cliConnection == nil)
    }

    @Test func reconnectCannotReuseThePreviousAccountCheck() async throws {
        let fixture = try CLIExecutableFixture(response: Data(), delay: 0.15)
        defer { fixture.remove() }
        let initial = GitHubCLIConnection(executablePath: fixture.executable.path, username: "octocat", apiBaseURL: "https://api.github.com")
        let session = GitHubSession(connection: initial)
        let pending = Task { try await session.client(baseURL: "https://api.github.com", buildType: .none) }
        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: fixture.arguments.path) { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(FileManager.default.fileExists(atPath: fixture.arguments.path))
        session.useCLI(.init(executablePath: fixture.executable.path, username: "other-user", apiBaseURL: "https://api.github.com"))
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(session.cliConnection?.username == "other-user")
    }
}
