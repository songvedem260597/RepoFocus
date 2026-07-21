import Foundation

public enum GitLabCLIStatus: Equatable, Sendable {
    case unavailable
    case disabled
    case signedOut
    case authenticated
}

public enum GitLabCLIError: LocalizedError, Equatable {
    case unavailable
    case signedOut
    case invalidResponse
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "Chưa cài GitLab CLI. Hãy cài `glab`, sau đó chạy `glab auth login`."
        case .signedOut:
            "GitLab CLI chưa đăng nhập. Hãy chạy `glab auth login` trước."
        case .invalidResponse:
            "GitLab trả về dữ liệu repository không hợp lệ."
        case let .commandFailed(message):
            message.isEmpty ? "Không thể đọc repository từ GitLab." : message
        }
    }
}

public protocol GitLabRepositoryFetching: Sendable {
    func status() -> GitLabCLIStatus
    func setConnectionEnabled(_ enabled: Bool)
    func fetchRepositories() async throws -> [GitHubRepository]
    func fetchDailyActivity(
        startDate: Date,
        endDate: Date,
        repositories: [GitHubRepository]
    ) async throws -> DailyActivitySnapshot
}

public extension GitLabRepositoryFetching {
    func fetchDailyActivity(
        startDate: Date,
        endDate: Date,
        repositories: [GitHubRepository]
    ) async throws -> DailyActivitySnapshot {
        DailyActivitySnapshot(date: startDate, pushes: [])
    }
}

public final class GitLabCLIClient: GitLabRepositoryFetching, @unchecked Sendable {
    private let executableURL: URL?
    private let defaults: UserDefaults
    private let disabledKey: String
    private let host: String

    public init(
        executableURL: URL? = GitLabCLIClient.defaultExecutableURL,
        defaults: UserDefaults = .standard,
        disabledKey: String = "gitlab.cli-connection-disabled",
        host: String = "gitlab.com"
    ) {
        self.executableURL = executableURL
        self.defaults = defaults
        self.disabledKey = disabledKey
        self.host = host
    }

    public func status() -> GitLabCLIStatus {
        guard !defaults.bool(forKey: disabledKey) else { return .disabled }
        guard executableURL != nil else { return .unavailable }
        guard let result = try? runGlab(["auth", "status", "--hostname", host]),
              result.exitCode == 0 else {
            return .signedOut
        }
        return .authenticated
    }

    public func setConnectionEnabled(_ enabled: Bool) {
        defaults.set(!enabled, forKey: disabledKey)
    }

    public func fetchRepositories() async throws -> [GitHubRepository] {
        try await Task.detached(priority: .userInitiated) { [self] in
            guard executableURL != nil else { throw GitLabCLIError.unavailable }
            guard status() == .authenticated else { throw GitLabCLIError.signedOut }

            var repositories: [GitHubRepository] = []
            var page = 1
            while true {
                let endpoint = "projects?membership=true&per_page=100&page=\(page)&order_by=last_activity_at&sort=desc"
                let result = try runGlab(["api", endpoint, "--hostname", host])
                guard result.exitCode == 0 else {
                    throw GitLabCLIError.commandFailed(
                        result.error.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                let pageRepositories = try Self.decodeProjects(result.outputData)
                repositories.append(contentsOf: pageRepositories)
                guard pageRepositories.count == 100 else { break }
                page += 1
            }
            return repositories
        }.value
    }

    public func fetchDailyActivity(
        startDate: Date,
        endDate: Date,
        repositories: [GitHubRepository]
    ) async throws -> DailyActivitySnapshot {
        try await Task.detached(priority: .userInitiated) { [self] in
            guard executableURL != nil else { throw GitLabCLIError.unavailable }
            guard status() == .authenticated else { throw GitLabCLIError.signedOut }

            let projectPairs: [(Int, String)] = repositories.compactMap { repository in
                guard repository.sourceProvider == .gitlab,
                      repository.id.hasPrefix("gitlab-"),
                      let id = Int(repository.id.dropFirst("gitlab-".count)) else { return nil }
                return (id, repository.nameWithOwner)
            }
            let projectNames = Dictionary(uniqueKeysWithValues: projectPairs)
            let dayFormatter = DateFormatter()
            dayFormatter.calendar = Calendar(identifier: .gregorian)
            dayFormatter.locale = Locale(identifier: "en_US_POSIX")
            dayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            dayFormatter.dateFormat = "yyyy-MM-dd"

            var events: [GitLabPushEvent] = []
            var page = 1
            while true {
                let endpoint = Self.apiEndpoint(path: "events", queryItems: [
                    URLQueryItem(name: "action", value: "pushed"),
                    URLQueryItem(name: "scope", value: "all"),
                    URLQueryItem(name: "after", value: dayFormatter.string(from: startDate)),
                    URLQueryItem(name: "before", value: dayFormatter.string(from: endDate)),
                    URLQueryItem(name: "sort", value: "desc"),
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: String(page))
                ])
                let result = try runGlab(["api", endpoint, "--hostname", host])
                guard result.exitCode == 0 else {
                    throw GitLabCLIError.commandFailed(result.error)
                }
                let pageEvents = try Self.decodePushEvents(result.outputData)
                events.append(contentsOf: pageEvents)
                guard pageEvents.count == 100 else { break }
                page += 1
            }

            var pushes: [DailyPushActivity] = []
            for event in events where event.createdAt >= startDate && event.createdAt < endDate {
                guard let push = event.pushData,
                      push.refType == "branch",
                      let branch = push.ref,
                      !branch.isEmpty else { continue }
                let repositoryName = projectNames[event.projectID]
                    ?? "GitLab project \(event.projectID)"
                let commits = enrichedCommits(
                    event: event,
                    repositoryName: repositoryName
                )
                pushes.append(DailyPushActivity(
                    id: "gitlab-\(event.id)",
                    repositoryName: repositoryName,
                    branchName: branch,
                    pushedAt: event.createdAt,
                    commitCount: max(push.commitCount ?? commits.count, commits.count),
                    distinctCommitCount: max(push.commitCount ?? commits.count, commits.count),
                    commits: commits,
                    beforeSHA: push.commitFrom,
                    headSHA: push.commitTo,
                    provider: .gitlab
                ))
            }
            return DailyActivitySnapshot(date: startDate, pushes: pushes)
        }.value
    }

    static func decodeProjects(_ data: Data) throws -> [GitHubRepository] {
        do {
            return try decoder.decode([GitLabProject].self, from: data).map(\.repository)
        } catch {
            throw GitLabCLIError.invalidResponse
        }
    }

    static func decodePushActivities(
        _ data: Data,
        startDate: Date,
        endDate: Date,
        projectNames: [Int: String]
    ) throws -> [DailyPushActivity] {
        try decodePushEvents(data).compactMap { event in
            guard event.createdAt >= startDate,
                  event.createdAt < endDate,
                  let push = event.pushData,
                  push.refType == "branch",
                  let branch = push.ref else { return nil }
            let fallbackCommit: [DailyCommitActivity]
            if let sha = push.commitTo, let title = push.commitTitle {
                fallbackCommit = [DailyCommitActivity(sha: sha, message: title)]
            } else {
                fallbackCommit = []
            }
            return DailyPushActivity(
                id: "gitlab-\(event.id)",
                repositoryName: projectNames[event.projectID] ?? "GitLab project \(event.projectID)",
                branchName: branch,
                pushedAt: event.createdAt,
                commitCount: push.commitCount ?? fallbackCommit.count,
                distinctCommitCount: push.commitCount ?? fallbackCommit.count,
                commits: fallbackCommit,
                beforeSHA: push.commitFrom,
                headSHA: push.commitTo,
                provider: .gitlab
            )
        }
    }

    private func enrichedCommits(
        event: GitLabPushEvent,
        repositoryName: String
    ) -> [DailyCommitActivity] {
        guard let push = event.pushData else { return [] }
        if let from = push.commitFrom,
           let to = push.commitTo,
           !Self.isZeroSHA(from),
           !Self.isZeroSHA(to) {
            do {
                let endpoint = Self.apiEndpoint(
                    path: "projects/\(event.projectID)/repository/compare",
                    queryItems: [
                        URLQueryItem(name: "from", value: from),
                        URLQueryItem(name: "to", value: to),
                        URLQueryItem(name: "straight", value: "true")
                    ]
                )
                let result = try runGlab(["api", endpoint, "--hostname", host])
                if result.exitCode == 0,
                   let comparison = try? Self.decoder.decode(GitLabComparison.self, from: result.outputData) {
                    return comparison.commits.map { commit in
                        DailyCommitActivity(
                            sha: commit.id,
                            message: commit.message ?? commit.title,
                            url: URL(string: "https://\(host)/\(repositoryName)/-/commit/\(commit.id)")
                        )
                    }
                }
            } catch {
                // The event summary below remains useful when compare is unavailable.
            }
        }
        guard let sha = push.commitTo, let title = push.commitTitle else { return [] }
        return [DailyCommitActivity(
            sha: sha,
            message: title,
            url: URL(string: "https://\(host)/\(repositoryName)/-/commit/\(sha)")
        )]
    }

    private static func decodePushEvents(_ data: Data) throws -> [GitLabPushEvent] {
        do {
            return try decoder.decode([GitLabPushEvent].self, from: data)
        } catch {
            throw GitLabCLIError.invalidResponse
        }
    }

    private static func apiEndpoint(path: String, queryItems: [URLQueryItem]) -> String {
        var components = URLComponents()
        components.queryItems = queryItems
        return path + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
    }

    private static func isZeroSHA(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0 == "0" }
    }

    private func runGlab(_ arguments: [String]) throws -> GitLabCommandResult {
        guard let executableURL else { throw GitLabCLIError.unavailable }
        let process = Process()
        let outputPipe = Pipe()
        let errorURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RepoFocus-glab-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: errorURL.path, contents: nil),
              let errorHandle = try? FileHandle(forWritingTo: errorURL) else {
            throw GitLabCLIError.commandFailed("Không thể tạo vùng đệm tạm cho GitLab CLI.")
        }
        defer {
            try? errorHandle.close()
            try? FileManager.default.removeItem(at: errorURL)
        }
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorHandle
        process.environment = ProcessInfo.processInfo.environment.merging([
            "LC_ALL": "C",
            "NO_PROMPT": "1",
            "GITLAB_HOST": host,
            "GL_HOST": host
        ]) { _, new in new }
        try process.run()
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try errorHandle.synchronize()
        let errorData = (try? Data(contentsOf: errorURL)) ?? Data()
        return GitLabCommandResult(
            outputData: outputData,
            errorData: errorData,
            exitCode: process.terminationStatus
        )
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            let regular = ISO8601DateFormatter()
            regular.formatOptions = [.withInternetDateTime]
            if let date = regular.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO 8601 date: \(value)"
            )
        }
        return decoder
    }()

    public static var defaultExecutableURL: URL? {
        [
            "/opt/homebrew/bin/glab",
            "/usr/local/bin/glab",
            "/usr/bin/glab"
        ]
        .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        .map { URL(fileURLWithPath: $0) }
    }
}

private struct GitLabCommandResult {
    let outputData: Data
    let errorData: Data
    let exitCode: Int32

    var output: String {
        String(data: outputData, encoding: .utf8) ?? ""
    }

    var error: String {
        let value = String(data: errorData, encoding: .utf8) ?? ""
        return value.isEmpty ? output : value
    }
}

private struct GitLabProject: Decodable {
    let id: Int
    let name: String
    let pathWithNamespace: String
    let webURL: URL
    let description: String?
    let visibility: String
    let archived: Bool
    let defaultBranch: String?
    let openIssuesCount: Int?
    let lastActivityAt: Date
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case pathWithNamespace = "path_with_namespace"
        case webURL = "web_url"
        case description
        case visibility
        case archived
        case defaultBranch = "default_branch"
        case openIssuesCount = "open_issues_count"
        case lastActivityAt = "last_activity_at"
        case updatedAt = "updated_at"
    }

    var repository: GitHubRepository {
        GitHubRepository(
            id: "gitlab-\(id)",
            name: name,
            nameWithOwner: pathWithNamespace,
            url: webURL,
            description: description,
            isPrivate: visibility == "private" || visibility == "internal",
            isArchived: archived,
            defaultBranch: defaultBranch,
            openIssueCount: openIssuesCount ?? 0,
            openPullRequestCount: 0,
            pushedAt: lastActivityAt,
            updatedAt: updatedAt ?? lastActivityAt,
            provider: .gitlab
        )
    }
}

private struct GitLabPushEvent: Decodable {
    struct PushData: Decodable {
        let commitCount: Int?
        let refType: String?
        let commitFrom: String?
        let commitTo: String?
        let ref: String?
        let commitTitle: String?

        enum CodingKeys: String, CodingKey {
            case commitCount = "commit_count"
            case refType = "ref_type"
            case commitFrom = "commit_from"
            case commitTo = "commit_to"
            case ref
            case commitTitle = "commit_title"
        }
    }

    let id: Int
    let projectID: Int
    let createdAt: Date
    let pushData: PushData?

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case createdAt = "created_at"
        case pushData = "push_data"
    }
}

private struct GitLabComparison: Decodable {
    struct Commit: Decodable {
        let id: String
        let title: String
        let message: String?
    }

    let commits: [Commit]
}
