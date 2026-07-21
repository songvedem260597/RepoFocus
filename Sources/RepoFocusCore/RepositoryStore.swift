import Combine
import Foundation

public enum ConnectionState: Equatable, Sendable {
    case sampleData
    case ready
    case syncing
    case connected
    case failed(String)
}

public enum LocalGitCheckState: Equatable, Sendable {
    case idle
    case checking
    case checked
    case failed(String)
}

@MainActor
public final class RepositoryStore: ObservableObject {
    @Published public private(set) var repositories: [RepositoryRecord]
    @Published public private(set) var lastSyncAt: Date?
    @Published public private(set) var connectionState: ConnectionState
    @Published public private(set) var persistenceError: String?
    @Published public private(set) var localGitCheckStates: [String: LocalGitCheckState] = [:]

    private let persistence: RepositoryPersisting
    private let tokenStore: TokenStoring
    private let githubClient: GitHubRepositoryFetching
    private let localGitChecker: any LocalGitStatusChecking

    public init(
        persistence: RepositoryPersisting = JSONRepositoryPersistence.live(),
        tokenStore: TokenStoring = GitHubCLITokenStore(),
        githubClient: GitHubRepositoryFetching = GitHubClient(),
        localGitChecker: any LocalGitStatusChecking = LocalGitStatusChecker(),
        useSampleDataWhenEmpty: Bool = true
    ) {
        self.persistence = persistence
        self.tokenStore = tokenStore
        self.githubClient = githubClient
        self.localGitChecker = localGitChecker

        do {
            if let database = try persistence.load() {
                repositories = Self.migrateSampleContent(database.repositories)
                lastSyncAt = database.lastSyncAt
            } else {
                repositories = useSampleDataWhenEmpty ? SampleData.repositories : []
                lastSyncAt = nil
            }

            let hasToken = try tokenStore.loadToken() != nil
            connectionState = hasToken ? .ready : .sampleData
        } catch {
            repositories = useSampleDataWhenEmpty ? SampleData.repositories : []
            lastSyncAt = nil
            connectionState = .failed(error.localizedDescription)
            persistenceError = error.localizedDescription
        }
    }

    public var focusedRepositories: [RepositoryRecord] {
        repositories
            .filter { $0.tracking.isFocused && $0.tracking.status != .archived }
            .sorted {
                if $0.tracking.focusOrder != $1.tracking.focusOrder {
                    return $0.tracking.focusOrder < $1.tracking.focusOrder
                }
                return $0.github.name.localizedStandardCompare($1.github.name) == .orderedAscending
            }
    }

    public var isUsingSampleData: Bool {
        !repositories.isEmpty && repositories.allSatisfy { $0.id.hasPrefix("sample-") }
    }

    public var needsAttentionRepositories: [RepositoryRecord] {
        repositories.filter(\.needsAttention).sorted(by: prioritySort)
    }

    public var completedRepositories: [RepositoryRecord] {
        repositories
            .filter { $0.tracking.status == .done || $0.tracking.status == .archived }
            .sorted { $0.tracking.modifiedAt > $1.tracking.modifiedAt }
    }

    public func repository(id: String?) -> RepositoryRecord? {
        guard let id else { return nil }
        return repositories.first { $0.id == id }
    }

    public func updateTracking(
        repositoryID: String,
        _ update: (inout RepositoryTracking) -> Void
    ) {
        guard let index = repositories.firstIndex(where: { $0.id == repositoryID }) else { return }
        update(&repositories[index].tracking)
        repositories[index].tracking.progress = min(max(repositories[index].tracking.progress, 0), 100)
        repositories[index].tracking.modifiedAt = .now
        persist()
    }

    public func toggleFocus(repositoryID: String) {
        updateTracking(repositoryID: repositoryID) { tracking in
            tracking.isFocused.toggle()
            if tracking.isFocused {
                tracking.focusOrder = (focusedRepositories.map(\.tracking.focusOrder).max() ?? -1) + 1
            }
        }
    }

    public func setLocalPath(repositoryID: String, path: String) {
        let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        updateTracking(repositoryID: repositoryID) { tracking in
            tracking.localPath = normalized.isEmpty ? nil : normalized
            tracking.gitStatus = nil
        }
        localGitCheckStates[repositoryID] = .idle
    }

    public func localGitCheckState(repositoryID: String) -> LocalGitCheckState {
        localGitCheckStates[repositoryID] ?? .idle
    }

    public func checkLocalGit(repositoryID: String) async {
        guard let repository = repository(id: repositoryID),
              let path = repository.tracking.localPath else {
            localGitCheckStates[repositoryID] = .failed(LocalGitStatusError.emptyPath.localizedDescription)
            return
        }

        localGitCheckStates[repositoryID] = .checking
        let checker = localGitChecker

        do {
            let status = try await Task.detached(priority: .userInitiated) {
                try checker.check(path: path)
            }.value
            updateTracking(repositoryID: repositoryID) { $0.gitStatus = status }
            localGitCheckStates[repositoryID] = .checked
        } catch {
            localGitCheckStates[repositoryID] = .failed(error.localizedDescription)
        }
    }

    public func checkAllLocalGit() async {
        let repositoryIDs = repositories.compactMap { repository in
            repository.tracking.localPath == nil ? nil : repository.id
        }
        for repositoryID in repositoryIDs {
            await checkLocalGit(repositoryID: repositoryID)
        }
    }

    public func refreshAll() async {
        await sync()
        await checkAllLocalGit()
    }

    public func connectAndSync(token: String) async {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            connectionState = .failed("Paste a fine-grained GitHub token first.")
            return
        }

        do {
            try tokenStore.saveToken(normalized)
            await sync()
        } catch {
            connectionState = .failed(error.localizedDescription)
        }
    }

    public func connectUsingCurrentCredentials() async {
        do {
            if let controller = tokenStore as? any TokenConnectionControlling {
                try controller.setConnectionEnabled(true)
            }
            guard let token = try tokenStore.loadToken(), !token.isEmpty else {
                connectionState = .failed(GitHubCLITokenError.unavailable.localizedDescription)
                return
            }
            connectionState = .ready
            await sync()
        } catch {
            connectionState = .failed(error.localizedDescription)
        }
    }

    public func sync() async {
        do {
            guard let token = try tokenStore.loadToken(), !token.isEmpty else {
                connectionState = .sampleData
                return
            }

            connectionState = .syncing
            let snapshots = try await githubClient.fetchRepositories(token: token)
            merge(snapshots)
            lastSyncAt = .now
            connectionState = .connected
            persist()
        } catch {
            connectionState = .failed(error.localizedDescription)
        }
    }

    public func disconnect() {
        do {
            if let controller = tokenStore as? any TokenConnectionControlling {
                try controller.setConnectionEnabled(false)
            } else {
                try tokenStore.deleteToken()
            }
            connectionState = .sampleData
        } catch {
            connectionState = .failed(error.localizedDescription)
        }
    }

    public func merge(_ snapshots: [GitHubRepository]) {
        let existingTracking = Dictionary(
            uniqueKeysWithValues: repositories.map { ($0.id, $0.tracking) }
        )

        repositories = snapshots.map { snapshot in
            var tracking = existingTracking[snapshot.id]
                ?? RepositoryTracking(repositoryID: snapshot.id)
            if snapshot.isArchived && existingTracking[snapshot.id] == nil {
                tracking.status = .archived
            }
            return RepositoryRecord(github: snapshot, tracking: tracking)
        }
        .sorted { lhs, rhs in
            (lhs.github.pushedAt ?? .distantPast) > (rhs.github.pushedAt ?? .distantPast)
        }
    }

    private func persist() {
        do {
            try persistence.save(
                RepositoryDatabase(repositories: repositories, lastSyncAt: lastSyncAt)
            )
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    private func prioritySort(_ lhs: RepositoryRecord, _ rhs: RepositoryRecord) -> Bool {
        if lhs.tracking.priority != rhs.tracking.priority {
            return lhs.tracking.priority.rawValue > rhs.tracking.priority.rawValue
        }
        return lhs.tracking.modifiedAt > rhs.tracking.modifiedAt
    }

    private static func migrateSampleContent(_ records: [RepositoryRecord]) -> [RepositoryRecord] {
        let templates = Dictionary(uniqueKeysWithValues: SampleData.repositories.map { ($0.id, $0) })
        let oldNextActions = [
            "sample-1": "Finish repository sync and empty states",
            "sample-2": "Decide the event schema",
            "sample-3": "Write the new onboarding page",
            "sample-4": "Review naming before the next release"
        ]
        let oldNotes = [
            "sample-1": "Keep the first release read-only with GitHub.",
            "sample-2": "Blocked until the schema is reviewed.",
            "sample-5": "Version 1.0 released."
        ]

        return records.map { record in
            guard let template = templates[record.id] else { return record }
            var migrated = record
            migrated.github = template.github

            if migrated.tracking.nextAction == oldNextActions[record.id] {
                migrated.tracking.nextAction = template.tracking.nextAction
            }
            if migrated.tracking.notes == oldNotes[record.id] {
                migrated.tracking.notes = template.tracking.notes
            }
            return migrated
        }
    }
}
