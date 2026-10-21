import Foundation

nonisolated protocol GitHubAPITransport: Sendable {
    func api(_ endpoint: String, body: Data?) async throws -> Data
}
