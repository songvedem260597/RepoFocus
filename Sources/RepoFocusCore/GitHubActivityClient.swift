import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct DailyCommitActivity: Codable, Hashable, Identifiable, Sendable {
    public var id: String { sha }
    public let sha: String
    public let message: String
    public let url: URL?

    public init(sha: String, message: String, url: URL? = nil) {
        self.sha = sha
        self.message = message
        self.url = url
    }

    public var subject: String {
        message.split(whereSeparator: \Character.isNewline).first.map(String.init) ?? message
    }
}

public struct DailyPushActivity: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let repositoryName: String
    public let branchName: String
    public let pushedAt: Date
    public let commitCount: Int
    public let distinctCommitCount: Int
    public let commits: [DailyCommitActivity]
    public let beforeSHA: String?
    public let headSHA: String?
    public let provider: RepositoryProvider?

    public init(
        id: String,
        repositoryName: String,
        branchName: String,
        pushedAt: Date,
        commitCount: Int,
        distinctCommitCount: Int,
        commits: [DailyCommitActivity],
        beforeSHA: String? = nil,
        headSHA: String? = nil,
        provider: RepositoryProvider? = nil
    ) {
        self.id = id
        self.repositoryName = repositoryName
        self.branchName = branchName
        self.pushedAt = pushedAt
        self.commitCount = commitCount
        self.distinctCommitCount = distinctCommitCount
        self.commits = commits
        self.beforeSHA = beforeSHA
        self.headSHA = headSHA
        self.provider = provider
    }

    public var sourceProvider: RepositoryProvider { provider ?? .github }
}

public struct DailyActivitySnapshot: Codable, Hashable, Sendable {
    public let date: Date
    public let pushes: [DailyPushActivity]
    public let fetchedAt: Date

    public init(date: Date, pushes: [DailyPushActivity], fetchedAt: Date = .now) {
        self.date = date
        self.pushes = pushes.sorted { $0.pushedAt > $1.pushedAt }
        self.fetchedAt = fetchedAt
    }

    public var totalPushes: Int { pushes.count }
    public var totalCommits: Int { pushes.reduce(0) { $0 + $1.commitCount } }
    public var repositoryCount: Int { Set(pushes.map(\.repositoryName)).count }
    public var branchCount: Int {
        Set(pushes.map { "\($0.repositoryName)\u{0}\($0.branchName)" }).count
    }
}

public enum CommitChangeCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case feature
    case fix
    case refactor
    case documentation
    case test
    case build
    case maintenance
    case other

    public var id: String { rawValue }

    public static func classify(_ message: String) -> CommitChangeCategory {
        let value = message
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if matches(value, prefixes: ["fix", "bugfix", "hotfix", "sua loi", "khac phuc"], words: [" bug ", " loi "]) {
            return .fix
        }
        if matches(value, prefixes: ["refactor", "cleanup", "restructure", "tai cau truc"], words: [" refactor "]) {
            return .refactor
        }
        if matches(value, prefixes: ["docs", "doc", "readme", "tai lieu"], words: [" readme ", " documentation "]) {
            return .documentation
        }
        if matches(value, prefixes: ["test", "spec", "kiem thu"], words: [" test ", " tests "]) {
            return .test
        }
        if matches(value, prefixes: ["build", "ci", "release"], words: [" workflow ", " pipeline ", " xcodeproj "]) {
            return .build
        }
        if matches(value, prefixes: ["chore", "deps", "dependency", "maintenance", "bao tri"], words: [" dependency ", " dependencies "]) {
            return .maintenance
        }
        if matches(
            value,
            prefixes: ["feat", "feature", "add", "create", "implement", "them", "bo sung", "tinh nang"],
            words: [" feature ", " chuc nang "]
        ) {
            return .feature
        }
        return .other
    }

    private static func matches(_ value: String, prefixes: [String], words: [String]) -> Bool {
        let padded = " \(value) "
        return prefixes.contains { prefix in
            value == prefix
                || value.hasPrefix("\(prefix):")
                || value.hasPrefix("\(prefix)(")
                || value.hasPrefix("\(prefix) ")
                || value.hasPrefix("\(prefix)-")
        } || words.contains(where: padded.contains)
    }
}

public protocol GitHubActivityFetching: Sendable {
    func fetchDailyActivity(
        token: String,
        startDate: Date,
        endDate: Date
    ) async throws -> DailyActivitySnapshot
}

public struct GitHubActivityClient: GitHubActivityFetching, Sendable {
    private let session: URLSession
    private let endpoint = URL(string: "https://api.github.com")!

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchDailyActivity(
        token: String,
        startDate: Date,
        endDate: Date
    ) async throws -> DailyActivitySnapshot {
        let login = try await fetchLogin(token: token)
        var pushes: [DailyPushActivity] = []

        for page in 1...3 {
            var components = URLComponents(
                url: endpoint
                    .appendingPathComponent("users")
                    .appendingPathComponent(login)
                    .appendingPathComponent("events"),
                resolvingAgainstBaseURL: false
            )!
            components.queryItems = [
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "page", value: String(page))
            ]
            guard let url = components.url else { throw GitHubAPIError.invalidResponse }

            let data = try await requestData(url: url, token: token)
            let events = try Self.decoder.decode([GitHubEvent].self, from: data)
            pushes.append(contentsOf: Self.pushActivities(
                from: events,
                startDate: startDate,
                endDate: endDate
            ))

            let reachedSelectedDay = events.compactMap(\.createdAt).min().map { $0 < startDate } ?? false
            if events.count < 100 || reachedSelectedDay { break }
        }

        let enrichedPushes = await withTaskGroup(of: DailyPushActivity.self) { group in
            for push in pushes {
                group.addTask {
                    await enriched(push, token: token)
                }
            }

            var result: [DailyPushActivity] = []
            for await push in group {
                result.append(push)
            }
            return result
        }

        return DailyActivitySnapshot(date: startDate, pushes: enrichedPushes)
    }

    private func fetchLogin(token: String) async throws -> String {
        let data = try await requestData(url: endpoint.appendingPathComponent("user"), token: token)
        return try Self.decoder.decode(AuthenticatedUser.self, from: data).login
    }

    private func requestData(url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("RepoFocus/0.7", forHTTPHeaderField: "User-Agent")

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
        return data
    }

    private func enriched(_ push: DailyPushActivity, token: String) async -> DailyPushActivity {
        guard let beforeSHA = push.beforeSHA,
              let headSHA = push.headSHA,
              !Self.isZeroSHA(beforeSHA),
              !Self.isZeroSHA(headSHA) else { return push }

        do {
            var url = endpoint.appendingPathComponent("repos")
            for component in push.repositoryName.split(separator: "/") {
                url.appendPathComponent(String(component))
            }
            url.appendPathComponent("compare")
            url.appendPathComponent("\(beforeSHA)...\(headSHA)")
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "per_page", value: "100")]
            guard let compareURL = components.url else { return push }

            let data = try await requestData(url: compareURL, token: token)
            let comparison = try Self.decoder.decode(CompareResponse.self, from: data)
            return DailyPushActivity(
                id: push.id,
                repositoryName: push.repositoryName,
                branchName: push.branchName,
                pushedAt: push.pushedAt,
                commitCount: comparison.totalCommits,
                distinctCommitCount: comparison.totalCommits,
                commits: comparison.commits.map {
                    DailyCommitActivity(sha: $0.sha, message: $0.commit.message, url: $0.htmlURL)
                },
                beforeSHA: beforeSHA,
                headSHA: headSHA,
                provider: .github
            )
        } catch {
            return push
        }
    }

    private static func isZeroSHA(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0 == "0" }
    }

    private static func pushActivities(
        from events: [GitHubEvent],
        startDate: Date,
        endDate: Date
    ) -> [DailyPushActivity] {
        events.compactMap { event in
            guard event.type == "PushEvent",
                  let createdAt = event.createdAt,
                  createdAt >= startDate,
                  createdAt < endDate,
                  let payload = event.payload,
                  let ref = payload.ref,
                  ref.hasPrefix("refs/heads/") else { return nil }

            return DailyPushActivity(
                id: event.id,
                repositoryName: event.repo.name,
                branchName: String(ref.dropFirst("refs/heads/".count)),
                pushedAt: createdAt,
                commitCount: payload.size ?? payload.commits?.count ?? 0,
                distinctCommitCount: payload.distinctSize ?? payload.commits?.count ?? 0,
                commits: (payload.commits ?? []).map {
                    DailyCommitActivity(sha: $0.sha, message: $0.message, url: $0.url)
                },
                beforeSHA: payload.before,
                headSHA: payload.head,
                provider: .github
            )
        }
    }

    static func decodePushActivities(
        from data: Data,
        startDate: Date,
        endDate: Date
    ) throws -> [DailyPushActivity] {
        let events = try decoder.decode([GitHubEvent].self, from: data)
        return pushActivities(from: events, startDate: startDate, endDate: endDate)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private struct AuthenticatedUser: Decodable {
    let login: String
}

private struct GitHubEvent: Decodable {
    struct Repository: Decodable {
        let name: String
    }

    struct Payload: Decodable {
        struct Commit: Decodable {
            let sha: String
            let message: String
            let url: URL?
        }

        let ref: String?
        let size: Int?
        let distinctSize: Int?
        let commits: [Commit]?
        let before: String?
        let head: String?

        enum CodingKeys: String, CodingKey {
            case ref
            case size
            case distinctSize = "distinct_size"
            case commits
            case before
            case head
        }
    }

    let id: String
    let type: String
    let repo: Repository
    let payload: Payload?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case repo
        case payload
        case createdAt = "created_at"
    }
}

private struct CompareResponse: Decodable {
    struct CommitItem: Decodable {
        struct GitCommit: Decodable {
            let message: String
        }

        let sha: String
        let htmlURL: URL?
        let commit: GitCommit

        enum CodingKeys: String, CodingKey {
            case sha
            case htmlURL = "html_url"
            case commit
        }
    }

    let totalCommits: Int
    let commits: [CommitItem]

    enum CodingKeys: String, CodingKey {
        case totalCommits = "total_commits"
        case commits
    }
}
