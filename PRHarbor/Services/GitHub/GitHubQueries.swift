import Foundation

/// The GraphQL documents the client sends. `GraphQLDocumentTests` exports them and
/// Scripts/validate-graphql.sh checks them against GitHub's schema.
nonisolated enum GitHubQueries {
    static func details(buildType: BuildType) -> String {
        let buildFields: String

        switch buildType {
        case .checks:
            buildFields = """
                commits(last: 1) {
                    nodes {
                        commit {
                            statusCheckRollup { state }
                            checkSuites(first: 10) {
                                nodes {
                                    app {
                                        name
                                    }
                                    checkRuns(first: 10) {
                                        nodes {
                                            name
                                            conclusion
                                            detailsUrl
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                """
        case .commitStatus:
            buildFields = """
                commits(last: 1) {
                    nodes {
                        commit {
                            statusCheckRollup {
                                state
                                contexts(first: 20) {
                                    nodes {
                                        ... on StatusContext {
                                            context
                                            description
                                            state
                                            targetUrl
                                        }
                                        ... on CheckRun {
                                            name
                                            conclusion
                                            detailsUrl
                                            title
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                """
        case .none:
            buildFields = ""
        }

        return """
            query PullRequestDetails($ids: [ID!]!) {
                nodes(ids: $ids) {
                    ... on PullRequest {
                        number
                        createdAt
                        updatedAt
                        title
                        headRefName
                        baseRefName
                        timelineItems(last: 60, itemTypes: [ISSUE_COMMENT, PULL_REQUEST_COMMIT, PULL_REQUEST_REVIEW, REVIEW_REQUESTED_EVENT]) {
                            pageInfo { hasPreviousPage }
                            nodes {
                                __typename
                                ... on IssueComment { createdAt author { login avatarUrl } }
                                ... on PullRequestCommit { commit { committedDate } }
                                ... on PullRequestReview { submittedAt state author { login avatarUrl } }
                                ... on ReviewRequestedEvent {
                                    createdAt
                                    requestedReviewer {
                                        __typename
                                        ... on User { login avatarUrl }
                                    }
                                }
                            }
                        }
                        reviewRequests(first: 30) {
                            nodes {
                                requestedReviewer {
                                    __typename
                                    ... on User { login avatarUrl }
                                }
                            }
                        }
                        url
                        isDraft
                        reviewDecision
                        mergeable
                        author {
                            login
                            avatarUrl
                        }
                        repository {
                            name
                            nameWithOwner
                        }
                        \(buildFields)
                    }
                }
            }
            """
    }

    /// Identity and the change markers `isCurrent` compares, without history or check details.
    static func summary(buildType: BuildType, includeStacks: Bool) -> String {
        let stackFields = includeStacks ? "stack { id number baseRefName size }\n stackEntry { position }" : ""
        let ciFields = buildType == .none ? "" : "commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }"
        return """
            query PullRequestSummaries($query: String!, $cursor: String, $pageSize: Int!) {
                viewer { login }
                search(query: $query, type: ISSUE, first: $pageSize, after: $cursor) {
                    pageInfo {
                        hasNextPage
                        endCursor
                    }
                    nodes {
                        ... on PullRequest {
                            id
                            url
                            updatedAt
                            isDraft
                            mergeable
                            \(stackFields)
                            \(ciFields)
                        }
                    }
                }
            }
            """
    }

    static func stackDetails() -> String {
        """
        query PullRequestStacks($ids: [ID!]!) {
            nodes(ids: $ids) {
                ... on PullRequestStack {
                    id
                    number
                    baseRefName
                    size
                    entries(first: 100) {
                        nodes {
                            position
                            pullRequest {
                                id
                                number
                                title
                                url
                                state
                                isDraft
                                headRefName
                                headRefOid
                                reviewDecision
                                mergeable
                            }
                        }
                    }
                }
            }
        }
        """
    }

    static let rebaseBranch = """
        mutation RebasePullRequestBranch($input: UpdatePullRequestBranchInput!) {
            updatePullRequestBranch(input: $input) {
                pullRequest {
                    id
                    headRefOid
                }
            }
        }
        """
}
