import Foundation

nonisolated struct GraphQLErrorResponse: Decodable, Sendable {
    let errors: [GraphQLError]
}

nonisolated struct GraphQLError: Decodable, Sendable {
    let message: String
    var type: String?
    var extensions: Extensions?

    /// Query validation errors identify the missing schema element; execution errors have a `type`.
    struct Extensions: Decodable, Sendable {
        var code: String?
        var typeName: String?
        var fieldName: String?
    }
}

nonisolated struct GraphQLAPIError: LocalizedError, Sendable {
    let errors: [GraphQLError]

    var errorDescription: String? {
        var seen: Set<String> = []
        return errors.map(\.message).filter { seen.insert($0).inserted }.joined(separator: "\n")
    }

    var isResourceLimit: Bool {
        errors.contains { $0.type == "RESOURCE_LIMITS_EXCEEDED" }
    }

    /// GitHub Enterprise versions without stacks reject the `stack` fields or the stack type.
    var isMissingStackSchema: Bool {
        errors.contains { error in
            guard let extensions = error.extensions,
                extensions.code == "undefinedField" || extensions.code == "undefinedType"
            else { return false }
            return [extensions.fieldName, extensions.typeName].contains { $0?.lowercased().contains("stack") == true }
        }
    }
}

nonisolated struct GraphQLRequest<Variables: Encodable>: Encodable {
    let query: String
    let variables: Variables
}

nonisolated struct GraphQLVariables: Encodable, Sendable {
    let searchQuery: String
    let cursor: String?
    var pageSize: Int = 20

    enum CodingKeys: String, CodingKey {
        case searchQuery = "query"
        case cursor
        case pageSize
    }
}

nonisolated struct GraphQLStackVariables: Encodable, Sendable {
    let ids: [String]
}

nonisolated struct GraphQLRebaseVariables: Encodable, Sendable {
    let input: Input

    struct Input: Encodable, Sendable {
        let pullRequestId: String
        let expectedHeadOid: String
        let updateMethod: String
    }
}

nonisolated struct GraphQLRebaseResponse: Decodable, Sendable {
    let data: Data

    struct Data: Decodable, Sendable {
        let updatePullRequestBranch: Payload?
    }

    struct Payload: Decodable, Sendable {
        let pullRequest: UpdatedPullRequest?
    }

    struct UpdatedPullRequest: Decodable, Sendable {
        let id: String
        let headRefOid: String
    }
}
