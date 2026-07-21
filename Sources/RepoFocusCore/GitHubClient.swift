import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol GitHubRepositoryFetching: Sendable {
    func fetchRepositories(token: String) async throws -> [GitHubRepository]
}

public enum GitHubAPIError: LocalizedError {
    case invalidResponse
    case httpStatus(Int, String)
    case graphQL([String])
    case missingData

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "GitHub returned an invalid response."
        case .httpStatus(let status, let message):
            "GitHub request failed (HTTP \(status)): \(message)"
        case .graphQL(let messages):
            messages.joined(separator: "\n")
        case .missingData:
            "GitHub returned no repository data."
        }
    }
}

public struct GitHubClient: GitHubRepositoryFetching, Sendable {
    private let session: URLSession
    private let endpoint = URL(string: "https://api.github.com/graphql")!

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchRepositories(token: String) async throws -> [GitHubRepository] {
        var repositories: [GitHubRepository] = []
        var cursor: String?

        repeat {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("RepoFocus/0.1", forHTTPHeaderField: "User-Agent")
            request.httpBody = try JSONEncoder().encode(
                GraphQLRequest(query: Self.repositoryQuery, variables: .init(cursor: cursor))
            )

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw GitHubAPIError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                throw GitHubAPIError.httpStatus(
                    http.statusCode,
                    String(data: data, encoding: .utf8) ?? "Unknown error"
                )
            }

            let decoded = try Self.decoder.decode(GraphQLResponse.self, from: data)
            if let errors = decoded.errors, !errors.isEmpty {
                throw GitHubAPIError.graphQL(errors.map(\.message))
            }
            guard let connection = decoded.data?.viewer.repositories else {
                throw GitHubAPIError.missingData
            }

            repositories.append(contentsOf: connection.nodes.map(\.repository))
            cursor = connection.pageInfo.hasNextPage ? connection.pageInfo.endCursor : nil
        } while cursor != nil

        return repositories
    }

    private static let repositoryQuery = """
    query RepoFocusRepositories($cursor: String) {
      viewer {
        repositories(
          first: 50
          after: $cursor
          affiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER]
          orderBy: { field: PUSHED_AT, direction: DESC }
        ) {
          nodes {
            id
            name
            nameWithOwner
            url
            description
            isPrivate
            isArchived
            pushedAt
            updatedAt
            primaryLanguage { name color }
            defaultBranchRef { name }
            issues(states: OPEN) { totalCount }
            pullRequests(states: OPEN) { totalCount }
          }
          pageInfo { hasNextPage endCursor }
        }
      }
      rateLimit { cost remaining resetAt }
    }
    """

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private struct GraphQLRequest: Encodable {
    struct Variables: Encodable {
        let cursor: String?
    }

    let query: String
    let variables: Variables
}

private struct GraphQLResponse: Decodable {
    struct Payload: Decodable {
        struct Viewer: Decodable {
            let repositories: RepositoryConnection
        }

        let viewer: Viewer
    }

    struct ErrorItem: Decodable {
        let message: String
    }

    let data: Payload?
    let errors: [ErrorItem]?
}

private struct RepositoryConnection: Decodable {
    struct PageInfo: Decodable {
        let hasNextPage: Bool
        let endCursor: String?
    }

    let nodes: [RepositoryNode]
    let pageInfo: PageInfo
}

private struct RepositoryNode: Decodable {
    struct Language: Decodable {
        let name: String
        let color: String?
    }

    struct Branch: Decodable {
        let name: String
    }

    struct Count: Decodable {
        let totalCount: Int
    }

    let id: String
    let name: String
    let nameWithOwner: String
    let url: URL
    let description: String?
    let isPrivate: Bool
    let isArchived: Bool
    let pushedAt: Date?
    let updatedAt: Date
    let primaryLanguage: Language?
    let defaultBranchRef: Branch?
    let issues: Count
    let pullRequests: Count

    var repository: GitHubRepository {
        GitHubRepository(
            id: id,
            name: name,
            nameWithOwner: nameWithOwner,
            url: url,
            description: description,
            isPrivate: isPrivate,
            isArchived: isArchived,
            primaryLanguage: primaryLanguage?.name,
            languageColor: primaryLanguage?.color,
            defaultBranch: defaultBranchRef?.name,
            openIssueCount: issues.totalCount,
            openPullRequestCount: pullRequests.totalCount,
            pushedAt: pushedAt,
            updatedAt: updatedAt
        )
    }
}
