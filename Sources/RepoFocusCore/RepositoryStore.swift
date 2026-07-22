import Combine
import Foundation

public enum ConnectionState: Equatable, Sendable {
    case sampleData
    case ready
    case syncing
    case connected
    case failed(String)
}

public enum GitLabConnectionState: Equatable, Sendable {
    case unavailable
    case disconnected
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

public enum LocalGitOperationState: Equatable, Sendable {
    case idle
    case running(LocalGitOperationKind)
    case succeeded(LocalGitOperationKind, String)
    case needsConflictResolution(LocalGitOperationKind, String)
    case failed(LocalGitOperationKind?, String)
}

public enum LocalRepositoryDetectionState: Equatable, Sendable {
    case idle
    case scanning
    case found
    case notFound
    case failed(String)
}

public enum RepositoryCloneState: Equatable, Sendable {
    case idle
    case cloning
    case succeeded(repositoryID: String, path: String)
    case failed(String)
}

public enum DailyActivityLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
}

@MainActor
public final class RepositoryStore: ObservableObject {
    @Published public private(set) var repositories: [RepositoryRecord]
    @Published public private(set) var lastSyncAt: Date?
    @Published public private(set) var connectionState: ConnectionState
    @Published public private(set) var gitLabConnectionState: GitLabConnectionState
    @Published public private(set) var persistenceError: String?
    @Published public private(set) var localGitCheckStates: [String: LocalGitCheckState] = [:]
    @Published public private(set) var localGitOperationStates: [String: LocalGitOperationState] = [:]
    @Published public private(set) var localGitConflictFiles: [String: [LocalGitConflictFile]] = [:]
    @Published public private(set) var localGitSequenceStates: [String: LocalGitSequenceState] = [:]
    @Published public private(set) var recentLocalCommits: [String: [LocalGitCommit]] = [:]
    @Published public private(set) var localRepositoryDetectionStates: [String: LocalRepositoryDetectionState] = [:]
    @Published public private(set) var cloneState: RepositoryCloneState = .idle
    @Published public private(set) var cloneProgress: LocalRepositoryCloneProgress?
    @Published public private(set) var activitySnapshots: [DailyActivitySnapshot]
    @Published public private(set) var activityLoadState: DailyActivityLoadState = .idle

    private let persistence: RepositoryPersisting
    private let tokenStore: TokenStoring
    private let githubClient: GitHubRepositoryFetching
    private let gitLabClient: any GitLabRepositoryFetching
    private let localGitChecker: any LocalGitStatusChecking
    private let localGitOperator: any LocalGitOperating
    private let localRepositoryLocator: any LocalRepositoryLocating
    private let localRepositoryCloner: any LocalRepositoryCloning
    private let githubActivityClient: any GitHubActivityFetching

    public init(
        persistence: RepositoryPersisting = JSONRepositoryPersistence.live(),
        tokenStore: TokenStoring = GitHubCLITokenStore(),
        githubClient: GitHubRepositoryFetching = GitHubClient(),
        gitLabClient: any GitLabRepositoryFetching = GitLabCLIClient(),
        localGitChecker: any LocalGitStatusChecking = LocalGitStatusChecker(),
        localGitOperator: any LocalGitOperating = LocalGitOperator(),
        localRepositoryLocator: any LocalRepositoryLocating = LocalRepositoryLocator(),
        localRepositoryCloner: any LocalRepositoryCloning = LocalRepositoryCloner(),
        githubActivityClient: any GitHubActivityFetching = GitHubActivityClient(),
        useSampleDataWhenEmpty: Bool = true
    ) {
        self.persistence = persistence
        self.tokenStore = tokenStore
        self.githubClient = githubClient
        self.gitLabClient = gitLabClient
        self.localGitChecker = localGitChecker
        self.localGitOperator = localGitOperator
        self.localRepositoryLocator = localRepositoryLocator
        self.localRepositoryCloner = localRepositoryCloner
        self.githubActivityClient = githubActivityClient

        do {
            if let database = try persistence.load() {
                repositories = Self.migrateBranchFocus(
                    Self.migrateSampleContent(database.repositories)
                )
                lastSyncAt = database.lastSyncAt
                activitySnapshots = database.activitySnapshots ?? []
            } else {
                repositories = useSampleDataWhenEmpty
                    ? Self.migrateBranchFocus(SampleData.repositories)
                    : []
                lastSyncAt = nil
                activitySnapshots = []
            }

            let hasToken = try tokenStore.loadToken() != nil
            connectionState = hasToken ? .ready : .sampleData
            gitLabConnectionState = Self.gitLabConnectionState(for: gitLabClient.status())
        } catch {
            repositories = useSampleDataWhenEmpty ? SampleData.repositories : []
            lastSyncAt = nil
            activitySnapshots = []
            connectionState = .failed(error.localizedDescription)
            gitLabConnectionState = Self.gitLabConnectionState(for: gitLabClient.status())
            persistenceError = error.localizedDescription
        }
    }

    public var isSyncingSources: Bool {
        connectionState == .syncing || gitLabConnectionState == .syncing
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

    public func todayReminderItems(
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> [RepositoryReminderItem] {
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date

        return focusedRepositories.compactMap { repository in
            guard repository.tracking.status != .done,
                  repository.tracking.status != .archived,
                  repository.tracking.status != .paused else { return nil }

            var reasons: [RepositoryReminderReason] = []
            if let deadline = repository.tracking.deadline {
                if deadline < startOfDay {
                    reasons.append(.overdue)
                } else if deadline < endOfDay {
                    reasons.append(.dueToday)
                }
            }
            if repository.tracking.status == .blocked {
                reasons.append(.blocked)
            }
            if repository.tracking.gitStatus?.hasConflicts == true {
                reasons.append(.conflicts)
            }

            return RepositoryReminderItem(
                repositoryID: repository.id,
                repositoryName: repository.github.name,
                branchName: repository.tracking.focusBranch
                    ?? repository.tracking.gitStatus?.branch
                    ?? repository.github.defaultBranch,
                nextAction: repository.tracking.nextAction,
                reasons: reasons,
                priority: repository.tracking.priority,
                focusOrder: repository.tracking.focusOrder
            )
        }
        .sorted { lhs, rhs in
            let lhsUrgency = Self.reminderUrgency(lhs)
            let rhsUrgency = Self.reminderUrgency(rhs)
            if lhsUrgency != rhsUrgency { return lhsUrgency > rhsUrgency }
            if lhs.priority != rhs.priority { return lhs.priority.rawValue > rhs.priority.rawValue }
            return lhs.focusOrder < rhs.focusOrder
        }
    }

    public func activitySnapshot(for date: Date, calendar: Calendar = .current) -> DailyActivitySnapshot? {
        activitySnapshots.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    public func loadDailyActivity(for date: Date, calendar: Calendar = .current) async {
        let startDate = calendar.startOfDay(for: date)
        guard let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) else {
            activityLoadState = .failed("Không thể xác định khoảng thời gian đã chọn.")
            return
        }

        var githubToken: String?
        var sourceErrors: [String] = []
        do {
            githubToken = try tokenStore.loadToken()
        } catch {
            sourceErrors.append(error.localizedDescription)
        }
        let canLoadGitLab = (gitLabConnectionState == .ready || gitLabConnectionState == .connected)
            && gitLabClient.status() == .authenticated
        guard githubToken?.isEmpty == false || canLoadGitLab else {
            activityLoadState = .failed(
                sourceErrors.first
                    ?? "Hãy kết nối GitHub hoặc GitLab để xem hoạt động theo ngày."
            )
            return
        }

        activityLoadState = .loading
        var pushes: [DailyPushActivity] = []
        var loadedSourceCount = 0

        if let githubToken, !githubToken.isEmpty {
            do {
                let snapshot = try await githubActivityClient.fetchDailyActivity(
                    token: githubToken,
                    startDate: startDate,
                    endDate: endDate
                )
                pushes.append(contentsOf: snapshot.pushes)
                loadedSourceCount += 1
            } catch {
                sourceErrors.append("GitHub: \(error.localizedDescription)")
            }
        }

        if canLoadGitLab {
            do {
                let snapshot = try await gitLabClient.fetchDailyActivity(
                    startDate: startDate,
                    endDate: endDate,
                    repositories: repositories.map(\.github)
                )
                pushes.append(contentsOf: snapshot.pushes)
                loadedSourceCount += 1
            } catch {
                sourceErrors.append("GitLab: \(error.localizedDescription)")
            }
        }

        guard loadedSourceCount > 0 else {
            activityLoadState = .failed(sourceErrors.joined(separator: "\n"))
            return
        }

        let snapshot = DailyActivitySnapshot(date: startDate, pushes: pushes)
        activitySnapshots.removeAll { calendar.isDate($0.date, inSameDayAs: startDate) }
        activitySnapshots.append(snapshot)
        activitySnapshots.sort { $0.date > $1.date }
        if activitySnapshots.count > 31 {
            activitySnapshots.removeLast(activitySnapshots.count - 31)
        }
        activityLoadState = .loaded
        persist()
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
        Self.recalculateOutlineProgress(&repositories[index].tracking)
        repositories[index].tracking.progress = min(max(repositories[index].tracking.progress, 0), 100)
        repositories[index].tracking.modifiedAt = .now
        Self.saveActiveBranchTracking(&repositories[index].tracking)
        persist()
    }

    public func setOutlinePlanEnabled(repositoryID: String, enabled: Bool) {
        updateTracking(repositoryID: repositoryID) { tracking in
            if enabled && tracking.usesOutlinePlan != true {
                tracking.manualProgress = tracking.progress
            } else if !enabled && tracking.usesOutlinePlan == true {
                tracking.progress = tracking.manualProgress ?? tracking.progress
                tracking.manualProgress = nil
            }
            tracking.usesOutlinePlan = enabled
            if tracking.planItems == nil {
                tracking.planItems = []
            }
        }
    }

    public func addPlanItem(
        repositoryID: String,
        title: String,
        estimatedMinutes: Int? = nil,
        makeNextAction: Bool = false
    ) {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return }

        updateTracking(repositoryID: repositoryID) { tracking in
            if makeNextAction {
                if tracking.usesOutlinePlan != true {
                    tracking.manualProgress = tracking.progress
                    tracking.usesOutlinePlan = true
                }
                if tracking.nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    tracking.nextAction = normalizedTitle
                }
            }
            var items = tracking.planItems ?? []
            items.append(RepositoryPlanItem(
                title: normalizedTitle,
                estimatedMinutes: estimatedMinutes
            ))
            tracking.planItems = items
        }
    }

    public func updatePlanItemEstimate(
        repositoryID: String,
        itemID: UUID,
        estimatedMinutes: Int?
    ) {
        updateTracking(repositoryID: repositoryID) { tracking in
            guard var items = tracking.planItems,
                  let index = items.firstIndex(where: { $0.id == itemID }) else { return }
            items[index].estimatedMinutes = estimatedMinutes.map { min(max($0, 1), 10_080) }
            tracking.planItems = items
        }
    }

    public func togglePlanItem(repositoryID: String, itemID: UUID) {
        updateTracking(repositoryID: repositoryID) { tracking in
            guard var items = tracking.planItems,
                  let index = items.firstIndex(where: { $0.id == itemID }) else { return }

            items[index].isCompleted.toggle()
            if items[index].isCompleted {
                items[index].completionSource = .manual
                items[index].matchedCommitSHA = nil
                items[index].completedAt = .now
            } else {
                items[index].completionSource = nil
                items[index].matchedCommitSHA = nil
                items[index].completedAt = nil
            }
            tracking.planItems = items
            Self.advanceNextActionIfNeeded(&tracking)
        }
    }

    public func updatePlanItemCommitKeyword(
        repositoryID: String,
        itemID: UUID,
        keyword: String
    ) {
        updateTracking(repositoryID: repositoryID) { tracking in
            guard var items = tracking.planItems,
                  let index = items.firstIndex(where: { $0.id == itemID }) else { return }
            items[index].commitKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            tracking.planItems = items
        }
    }

    public func removePlanItem(repositoryID: String, itemID: UUID) {
        updateTracking(repositoryID: repositoryID) { tracking in
            guard let removedItem = tracking.planItems?.first(where: { $0.id == itemID }) else { return }
            tracking.planItems?.removeAll { $0.id == itemID }
            if Self.normalizedCommitText(tracking.nextAction)
                == Self.normalizedCommitText(removedItem.title) {
                tracking.nextAction = ""
            }
            Self.advanceNextActionIfNeeded(&tracking)
        }
    }

    public func toggleFocus(repositoryID: String) {
        guard let repository = repository(id: repositoryID) else { return }
        let nextOrder = (focusedRepositories.map(\.tracking.focusOrder).max() ?? -1) + 1
        let suggestedBranch = repository.tracking.focusBranch
            ?? repository.tracking.gitStatus?.branch
            ?? repository.github.defaultBranch
            ?? "main"

        updateTracking(repositoryID: repositoryID) { tracking in
            if tracking.isFocused {
                Self.saveActiveBranchTracking(&tracking)
            }
            tracking.isFocused.toggle()
            if tracking.isFocused {
                tracking.focusOrder = nextOrder
                Self.activateBranch(suggestedBranch, in: &tracking, preserveCurrentValues: true)
            }
        }
    }

    public func setFocusBranch(repositoryID: String, branchName: String) {
        let normalized = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        updateTracking(repositoryID: repositoryID) { tracking in
            Self.saveActiveBranchTracking(&tracking)
            Self.activateBranch(normalized, in: &tracking, preserveCurrentValues: false)
        }
    }

    public func setLocalPath(repositoryID: String, path: String) {
        let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        updateTracking(repositoryID: repositoryID) { tracking in
            tracking.localPath = normalized.isEmpty ? nil : normalized
            tracking.gitStatus = nil
        }
        localGitCheckStates[repositoryID] = .idle
        localGitOperationStates[repositoryID] = .idle
        localGitConflictFiles[repositoryID] = []
        localGitSequenceStates[repositoryID] = LocalGitSequenceState.none
        recentLocalCommits[repositoryID] = []
    }

    public func localGitCheckState(repositoryID: String) -> LocalGitCheckState {
        localGitCheckStates[repositoryID] ?? .idle
    }

    public func localGitOperationState(repositoryID: String) -> LocalGitOperationState {
        localGitOperationStates[repositoryID] ?? .idle
    }

    public func dismissLocalGitOperationResult(repositoryID: String) {
        localGitOperationStates[repositoryID] = .idle
    }

    public func localRepositoryDetectionState(repositoryID: String) -> LocalRepositoryDetectionState {
        localRepositoryDetectionStates[repositoryID] ?? .idle
    }

    public func resetCloneState() {
        cloneState = .idle
        cloneProgress = nil
    }

    public static var defaultCloneParentDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = ["Developer", "Projects", "Code", "Documents"]
            .map { home.appendingPathComponent($0, isDirectory: true) }
        return candidates.first { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }?.path ?? home.path
    }

    @discardableResult
    public func cloneRepository(
        repositoryID: String?,
        remoteURL: String,
        destinationParent: String
    ) async -> String? {
        cloneState = .cloning
        cloneProgress = .preparing
        let cloner = localRepositoryCloner
        let progressHandler: @Sendable (LocalRepositoryCloneProgress) -> Void = { [weak self] progress in
            Task { @MainActor [weak self] in
                guard let self, self.cloneState == .cloning else { return }
                guard progress.fractionCompleted >= (self.cloneProgress?.fractionCompleted ?? 0) else {
                    return
                }
                self.cloneProgress = progress
            }
        }

        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try cloner.clone(
                    remoteURL: remoteURL,
                    destinationParent: destinationParent,
                    progressHandler: progressHandler
                )
            }.value
            cloneProgress = .completed

            let resolvedRepositoryID = repositoryID
                ?? matchingRepositoryID(for: remoteURL)
                ?? addExternalRepository(remoteURL: remoteURL, cloneResult: result)

            updateTracking(repositoryID: resolvedRepositoryID) { tracking in
                tracking.localPath = result.path
                tracking.cloneSourceURL = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
                tracking.gitStatus = nil
            }
            await checkLocalGit(repositoryID: resolvedRepositoryID)
            cloneState = .succeeded(repositoryID: resolvedRepositoryID, path: result.path)
            return resolvedRepositoryID
        } catch {
            cloneState = .failed(error.localizedDescription)
            return nil
        }
    }

    public func autoDetectLocalRepositories(repositoryID: String? = nil) async {
        let candidates = repositories.filter { repository in
            guard repository.tracking.localPath == nil else { return false }
            return repositoryID == nil || repository.id == repositoryID
        }
        guard !candidates.isEmpty else { return }

        for repository in candidates {
            localRepositoryDetectionStates[repository.id] = .scanning
        }

        let locator = localRepositoryLocator
        let snapshots = candidates.map(\.github)

        do {
            let matches = try await Task.detached(priority: .utility) {
                try locator.locate(repositories: snapshots)
            }.value

            for repository in candidates {
                guard let index = repositories.firstIndex(where: { $0.id == repository.id }) else { continue }
                if let path = matches[repository.id] {
                    repositories[index].tracking.localPath = path
                    repositories[index].tracking.modifiedAt = .now
                    localRepositoryDetectionStates[repository.id] = .found
                } else {
                    localRepositoryDetectionStates[repository.id] = .notFound
                }
            }
            persist()

            if repositoryID != nil {
                for matchedRepositoryID in matches.keys {
                    await checkLocalGit(repositoryID: matchedRepositoryID)
                }
            }
        } catch {
            for repository in candidates {
                localRepositoryDetectionStates[repository.id] = .failed(error.localizedDescription)
            }
        }
    }

    public func checkLocalGit(repositoryID: String) async {
        guard let repository = repository(id: repositoryID),
              let path = repository.tracking.localPath else {
            localGitCheckStates[repositoryID] = .failed(LocalGitStatusError.emptyPath.localizedDescription)
            return
        }

        localGitCheckStates[repositoryID] = .checking
        let checker = localGitChecker
        let gitOperator = localGitOperator

        do {
            let result = try await Task.detached(priority: .userInitiated) {
                let status = try checker.check(path: path)
                let branches = try checker.branches(path: path)
                let planBranch = repository.tracking.focusBranch ?? status.branch
                let planCommits = try checker.recentCommits(
                    path: path,
                    branch: planBranch,
                    limit: 100
                )
                let currentCommits: [LocalGitCommit]
                if planBranch == status.branch {
                    currentCommits = planCommits
                } else {
                    currentCommits = try checker.recentCommits(
                        path: path,
                        branch: status.branch,
                        limit: 100
                    )
                }
                let conflicts = (try? gitOperator.conflictedFiles(path: path)) ?? []
                let sequence = (try? gitOperator.sequenceState(path: path)) ?? .none
                return (
                    status: status,
                    planCommits: planCommits,
                    currentCommits: currentCommits,
                    branches: branches,
                    conflicts: conflicts,
                    sequence: sequence
                )
            }.value
            updateTracking(repositoryID: repositoryID) { tracking in
                tracking.gitStatus = result.status
                tracking.localBranches = result.branches
                if tracking.isFocused && tracking.focusBranch == nil,
                   let branch = result.status.branch ?? result.branches.first {
                    Self.activateBranch(branch, in: &tracking, preserveCurrentValues: true)
                }
                Self.completePlanItems(in: &tracking, using: result.planCommits)
            }
            recentLocalCommits[repositoryID] = result.currentCommits
            localGitConflictFiles[repositoryID] = result.conflicts
            localGitSequenceStates[repositoryID] = result.sequence
            localGitCheckStates[repositoryID] = .checked
        } catch {
            localGitCheckStates[repositoryID] = .failed(error.localizedDescription)
        }
    }

    public func switchLocalBranch(repositoryID: String, branch: String) async {
        await performLocalGitOperation(repositoryID: repositoryID, kind: .switchBranch) { git, path in
            try git.switchBranch(path: path, branch: branch)
        }
        if case .succeeded = localGitOperationState(repositoryID: repositoryID),
           let currentBranch = repository(id: repositoryID)?.tracking.gitStatus?.branch {
            setFocusBranch(repositoryID: repositoryID, branchName: currentBranch)
        }
    }

    public func commitAll(repositoryID: String, message: String) async {
        await performLocalGitOperation(repositoryID: repositoryID, kind: .commit) { git, path in
            try git.commitAll(path: path, message: message)
        }
    }

    public func pull(repositoryID: String) async {
        await performLocalGitOperation(repositoryID: repositoryID, kind: .pull) { git, path in
            try git.pull(path: path)
        }
    }

    public func push(repositoryID: String) async {
        await performLocalGitOperation(repositoryID: repositoryID, kind: .push) { git, path in
            try git.push(path: path)
        }
    }

    public func revert(repositoryID: String, sha: String) async {
        await performLocalGitOperation(repositoryID: repositoryID, kind: .revert) { git, path in
            try git.revert(path: path, sha: sha)
        }
    }

    public func mergeLocalBranch(repositoryID: String, branch: String) async {
        await performLocalGitOperation(repositoryID: repositoryID, kind: .merge) { git, path in
            try git.merge(path: path, branch: branch)
        }
    }

    public func resolveLocalConflict(
        repositoryID: String,
        file: String,
        choice: LocalGitConflictChoice
    ) async {
        await performLocalGitOperation(repositoryID: repositoryID, kind: .resolveConflict) { git, path in
            try git.resolveConflict(path: path, file: file, choice: choice)
        }
    }

    public func continueLocalGitOperation(repositoryID: String) async {
        let sequence = localGitSequenceStates[repositoryID] ?? .none
        await performLocalGitOperation(repositoryID: repositoryID, kind: .continueOperation) { git, path in
            try git.continueOperation(path: path, state: sequence)
        }
    }

    public func abortLocalGitOperation(repositoryID: String) async {
        let sequence = localGitSequenceStates[repositoryID] ?? .none
        await performLocalGitOperation(repositoryID: repositoryID, kind: .abortOperation) { git, path in
            try git.abortOperation(path: path, state: sequence)
        }
    }

    private func performLocalGitOperation(
        repositoryID: String,
        kind: LocalGitOperationKind,
        action: @escaping @Sendable (any LocalGitOperating, String) throws -> LocalGitOperationResult
    ) async {
        guard let path = repository(id: repositoryID)?.tracking.localPath,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            localGitOperationStates[repositoryID] = .failed(kind, LocalGitOperationError.emptyPath.localizedDescription)
            return
        }

        localGitOperationStates[repositoryID] = .running(kind)
        let gitOperator = localGitOperator
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try action(gitOperator, path)
            }.value
            await checkLocalGit(repositoryID: repositoryID)
            let hasPendingResolution = !(localGitConflictFiles[repositoryID] ?? []).isEmpty
                || (localGitSequenceStates[repositoryID] ?? .none) != .none
            if hasPendingResolution && kind != .abortOperation {
                localGitOperationStates[repositoryID] = .needsConflictResolution(kind, result.message)
            } else {
                localGitOperationStates[repositoryID] = .succeeded(kind, result.message)
            }
        } catch {
            let message = error.localizedDescription
            await checkLocalGit(repositoryID: repositoryID)
            let hasPendingResolution = !(localGitConflictFiles[repositoryID] ?? []).isEmpty
                || (localGitSequenceStates[repositoryID] ?? .none) != .none
            localGitOperationStates[repositoryID] = hasPendingResolution
                ? .needsConflictResolution(kind, message)
                : .failed(kind, message)
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
        if gitLabConnectionState == .ready || gitLabConnectionState == .connected {
            await syncGitLab()
        }
        await autoDetectLocalRepositories()
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

    public func connectGitLabUsingCurrentCredentials() async {
        gitLabClient.setConnectionEnabled(true)
        switch gitLabClient.status() {
        case .authenticated:
            gitLabConnectionState = .ready
            await syncGitLab()
        case .unavailable:
            gitLabConnectionState = .unavailable
        case .disabled, .signedOut:
            gitLabConnectionState = .failed(GitLabCLIError.signedOut.localizedDescription)
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

    public func syncGitLab() async {
        switch gitLabClient.status() {
        case .unavailable:
            gitLabConnectionState = .unavailable
            return
        case .disabled:
            gitLabConnectionState = .disconnected
            return
        case .signedOut:
            gitLabConnectionState = .failed(GitLabCLIError.signedOut.localizedDescription)
            return
        case .authenticated:
            break
        }

        do {
            gitLabConnectionState = .syncing
            let snapshots = try await gitLabClient.fetchRepositories()
            merge(snapshots, source: .gitlab)
            lastSyncAt = .now
            gitLabConnectionState = .connected
            persist()
        } catch {
            gitLabConnectionState = .failed(error.localizedDescription)
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

    public func disconnectGitLab() {
        gitLabClient.setConnectionEnabled(false)
        gitLabConnectionState = .disconnected
    }

    public func merge(_ snapshots: [GitHubRepository]) {
        merge(snapshots, source: .github)
    }

    private func merge(_ snapshots: [GitHubRepository], source: RepositoryProvider) {
        let existingTracking = Dictionary(
            uniqueKeysWithValues: repositories.map { ($0.id, $0.tracking) }
        )

        var preservedRepositories = repositories.filter {
            !$0.id.hasPrefix("sample-")
                && ($0.id.hasPrefix("external-") || $0.github.sourceProvider != source)
        }

        let mergedRepositories = snapshots.map { snapshot in
            let matchingExternalIndex = preservedRepositories.firstIndex { existing in
                existing.id.hasPrefix("external-")
                    && existing.github.sourceProvider == snapshot.sourceProvider
                    && existing.github.nameWithOwner.caseInsensitiveCompare(snapshot.nameWithOwner) == .orderedSame
            }
            var tracking: RepositoryTracking
            if let existing = existingTracking[snapshot.id] {
                tracking = existing
            } else if let matchingExternalIndex {
                tracking = preservedRepositories.remove(at: matchingExternalIndex).tracking
                tracking.repositoryID = snapshot.id
            } else {
                tracking = RepositoryTracking(repositoryID: snapshot.id)
            }
            if snapshot.isArchived && existingTracking[snapshot.id] == nil {
                tracking.status = .archived
            }
            return RepositoryRecord(github: snapshot, tracking: tracking)
        }

        repositories = (mergedRepositories + preservedRepositories)
        .sorted { lhs, rhs in
            (lhs.github.pushedAt ?? .distantPast) > (rhs.github.pushedAt ?? .distantPast)
        }
    }

    private static func gitLabConnectionState(for status: GitLabCLIStatus) -> GitLabConnectionState {
        switch status {
        case .unavailable: .unavailable
        case .disabled: .disconnected
        case .signedOut: .disconnected
        case .authenticated: .ready
        }
    }

    private func persist() {
        do {
            try persistence.save(
                RepositoryDatabase(
                    repositories: repositories,
                    lastSyncAt: lastSyncAt,
                    activitySnapshots: activitySnapshots
                )
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

    private static func reminderUrgency(_ item: RepositoryReminderItem) -> Int {
        if item.reasons.contains(.overdue) { return 4 }
        if item.reasons.contains(.dueToday) { return 3 }
        if item.reasons.contains(.blocked) { return 2 }
        if item.reasons.contains(.conflicts) { return 1 }
        return 0
    }

    private func matchingRepositoryID(for remoteURL: String) -> String? {
        guard let identity = LocalRepositoryLocator.normalizedRemoteIdentity(remoteURL) else { return nil }
        return repositories.first {
            $0.github.sourceProvider == identity.provider
                && $0.github.nameWithOwner.caseInsensitiveCompare(identity.path) == .orderedSame
        }?.id
    }

    private func addExternalRepository(
        remoteURL: String,
        cloneResult: LocalRepositoryCloneResult
    ) -> String {
        let normalizedRemote = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let repositoryID = "external-\(Self.stableIdentifier(normalizedRemote))"
        if repositories.contains(where: { $0.id == repositoryID }) {
            return repositoryID
        }

        let identity = LocalRepositoryLocator.normalizedRemoteIdentity(normalizedRemote)
        let displayURL = Self.safeDisplayURL(for: normalizedRemote, fallbackPath: cloneResult.path)
        let github = GitHubRepository(
            id: repositoryID,
            name: cloneResult.folderName,
            nameWithOwner: identity?.path ?? cloneResult.folderName,
            url: displayURL,
            description: nil,
            defaultBranch: nil,
            updatedAt: .now,
            provider: identity?.provider
        )
        var tracking = RepositoryTracking(repositoryID: repositoryID)
        tracking.localPath = cloneResult.path
        tracking.cloneSourceURL = normalizedRemote
        repositories.append(RepositoryRecord(github: github, tracking: tracking))
        persist()
        return repositoryID
    }

    private static func safeDisplayURL(for remoteURL: String, fallbackPath: String) -> URL {
        if let identity = LocalRepositoryLocator.normalizedRemoteIdentity(remoteURL),
           identity.provider != .other,
           let url = URL(string: "https://\(identity.host)/\(identity.path)") {
            return url
        }
        if var components = URLComponents(string: remoteURL),
           let scheme = components.scheme,
           ["http", "https"].contains(scheme.lowercased()) {
            components.user = nil
            components.password = nil
            if let url = components.url { return url }
        }
        return URL(fileURLWithPath: fallbackPath, isDirectory: true)
    }

    private static func stableIdentifier(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static func saveActiveBranchTracking(_ tracking: inout RepositoryTracking) {
        guard tracking.isFocused,
              let branchName = tracking.focusBranch,
              !branchName.isEmpty else { return }

        let branchTracking = RepositoryBranchTracking(
            branchName: branchName,
            status: tracking.status,
            priority: tracking.priority,
            progress: tracking.progress,
            nextAction: tracking.nextAction,
            notes: tracking.notes,
            deadline: tracking.deadline,
            usesOutlinePlan: tracking.usesOutlinePlan,
            planItems: tracking.planItems,
            manualProgress: tracking.manualProgress,
            modifiedAt: tracking.modifiedAt
        )
        var branchTrackings = tracking.branchTrackings ?? []
        if let index = branchTrackings.firstIndex(where: { $0.branchName == branchName }) {
            branchTrackings[index] = branchTracking
        } else {
            branchTrackings.append(branchTracking)
        }
        tracking.branchTrackings = branchTrackings
    }

    private static func activateBranch(
        _ branchName: String,
        in tracking: inout RepositoryTracking,
        preserveCurrentValues: Bool
    ) {
        let normalized = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        tracking.focusBranch = normalized
        if let branchTracking = tracking.branchTrackings?.first(where: { $0.branchName == normalized }) {
            tracking.status = branchTracking.status
            tracking.priority = branchTracking.priority
            tracking.progress = branchTracking.progress
            tracking.nextAction = branchTracking.nextAction
            tracking.notes = branchTracking.notes
            tracking.deadline = branchTracking.deadline
            tracking.usesOutlinePlan = branchTracking.usesOutlinePlan
            tracking.planItems = branchTracking.planItems
            tracking.manualProgress = branchTracking.manualProgress
        } else if !preserveCurrentValues {
            tracking.status = .inbox
            tracking.priority = .medium
            tracking.progress = 0
            tracking.nextAction = ""
            tracking.notes = ""
            tracking.deadline = nil
            tracking.usesOutlinePlan = nil
            tracking.planItems = nil
            tracking.manualProgress = nil
        }
        saveActiveBranchTracking(&tracking)
    }

    private static func recalculateOutlineProgress(_ tracking: inout RepositoryTracking) {
        guard tracking.usesOutlinePlan == true else { return }
        let items = tracking.planItems ?? []
        guard !items.isEmpty else {
            tracking.progress = 0
            return
        }
        let completedCount = items.filter(\.isCompleted).count
        tracking.progress = Int((Double(completedCount) / Double(items.count) * 100).rounded())
    }

    private static func completePlanItems(
        in tracking: inout RepositoryTracking,
        using commits: [LocalGitCommit]
    ) {
        guard tracking.usesOutlinePlan == true,
              var items = tracking.planItems,
              !items.isEmpty else { return }

        for index in items.indices where !items[index].isCompleted {
            let keyword = normalizedCommitText(items[index].commitKeyword)
            guard !keyword.isEmpty else { continue }

            guard let match = commits.first(where: { commit in
                commit.committedAt >= items[index].createdAt &&
                    normalizedCommitText(commit.subject).contains(keyword)
            }) else { continue }

            items[index].isCompleted = true
            items[index].completionSource = .commit
            items[index].matchedCommitSHA = match.sha
            items[index].completedAt = match.committedAt
        }

        tracking.planItems = items
        advanceNextActionIfNeeded(&tracking)
        recalculateOutlineProgress(&tracking)
    }

    private static func advanceNextActionIfNeeded(_ tracking: inout RepositoryTracking) {
        guard tracking.usesOutlinePlan == true else { return }
        let items = tracking.planItems ?? []
        let current = normalizedCommitText(tracking.nextAction)

        if let currentItem = items.first(where: {
            normalizedCommitText($0.title) == current
        }), !currentItem.isCompleted {
            return
        }

        let currentBelongsToPlan = current.isEmpty || items.contains {
            normalizedCommitText($0.title) == current
        }
        guard currentBelongsToPlan else { return }
        tracking.nextAction = items.first(where: { !$0.isCompleted })?.title ?? ""
    }

    private static func normalizedCommitText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }

    private static func migrateBranchFocus(_ records: [RepositoryRecord]) -> [RepositoryRecord] {
        records.map { record in
            guard record.tracking.isFocused else { return record }
            var migrated = record
            let branchName = migrated.tracking.focusBranch
                ?? migrated.tracking.gitStatus?.branch
                ?? migrated.github.defaultBranch
                ?? "main"
            activateBranch(branchName, in: &migrated.tracking, preserveCurrentValues: true)
            return migrated
        }
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
