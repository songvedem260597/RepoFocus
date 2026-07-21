import Foundation

public enum WorkStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case inbox
    case planned
    case active
    case blocked
    case paused
    case done
    case archived

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .inbox: "Inbox"
        case .planned: "Planned"
        case .active: "Active"
        case .blocked: "Blocked"
        case .paused: "Paused"
        case .done: "Done"
        case .archived: "Archived"
        }
    }

    public var symbolName: String {
        switch self {
        case .inbox: "tray"
        case .planned: "calendar"
        case .active: "bolt.fill"
        case .blocked: "exclamationmark.octagon.fill"
        case .paused: "pause.fill"
        case .done: "checkmark.circle.fill"
        case .archived: "archivebox.fill"
        }
    }
}

public enum WorkPriority: Int, Codable, CaseIterable, Identifiable, Sendable {
    case low = 0
    case medium = 1
    case high = 2

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

public enum PlanCompletionSource: String, Codable, Sendable {
    case manual
    case commit
}

public struct RepositoryPlanItem: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var commitKeyword: String
    public var isCompleted: Bool
    public var completionSource: PlanCompletionSource?
    public var matchedCommitSHA: String?
    public var createdAt: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        commitKeyword: String? = nil,
        isCompleted: Bool = false,
        completionSource: PlanCompletionSource? = nil,
        matchedCommitSHA: String? = nil,
        createdAt: Date = .now,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.commitKeyword = commitKeyword ?? title
        self.isCompleted = isCompleted
        self.completionSource = completionSource
        self.matchedCommitSHA = matchedCommitSHA
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

public struct RepositoryBranchTracking: Codable, Hashable, Identifiable, Sendable {
    public var id: String { branchName }
    public let branchName: String
    public var status: WorkStatus
    public var priority: WorkPriority
    public var progress: Int
    public var nextAction: String
    public var notes: String
    public var deadline: Date?
    public var usesOutlinePlan: Bool?
    public var planItems: [RepositoryPlanItem]?
    public var manualProgress: Int?
    public var modifiedAt: Date

    public init(
        branchName: String,
        status: WorkStatus = .inbox,
        priority: WorkPriority = .medium,
        progress: Int = 0,
        nextAction: String = "",
        notes: String = "",
        deadline: Date? = nil,
        usesOutlinePlan: Bool? = nil,
        planItems: [RepositoryPlanItem]? = nil,
        manualProgress: Int? = nil,
        modifiedAt: Date = .now
    ) {
        self.branchName = branchName
        self.status = status
        self.priority = priority
        self.progress = min(max(progress, 0), 100)
        self.nextAction = nextAction
        self.notes = notes
        self.deadline = deadline
        self.usesOutlinePlan = usesOutlinePlan
        self.planItems = planItems
        self.manualProgress = manualProgress
        self.modifiedAt = modifiedAt
    }
}

public enum RepositoryProvider: String, Codable, CaseIterable, Hashable, Sendable {
    case github
    case gitlab
    case other

    public static func infer(from url: URL) -> RepositoryProvider {
        switch url.host?.lowercased() {
        case "github.com", "www.github.com": .github
        case "gitlab.com", "www.gitlab.com": .gitlab
        default: .other
        }
    }
}

public struct GitHubRepository: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let nameWithOwner: String
    public let url: URL
    public let description: String?
    public let isPrivate: Bool
    public let isArchived: Bool
    public let primaryLanguage: String?
    public let languageColor: String?
    public let defaultBranch: String?
    public let openIssueCount: Int
    public let openPullRequestCount: Int
    public let pushedAt: Date?
    public let updatedAt: Date
    public let provider: RepositoryProvider?

    public init(
        id: String,
        name: String,
        nameWithOwner: String,
        url: URL,
        description: String? = nil,
        isPrivate: Bool = false,
        isArchived: Bool = false,
        primaryLanguage: String? = nil,
        languageColor: String? = nil,
        defaultBranch: String? = nil,
        openIssueCount: Int = 0,
        openPullRequestCount: Int = 0,
        pushedAt: Date? = nil,
        updatedAt: Date = .now,
        provider: RepositoryProvider? = nil
    ) {
        self.id = id
        self.name = name
        self.nameWithOwner = nameWithOwner
        self.url = url
        self.description = description
        self.isPrivate = isPrivate
        self.isArchived = isArchived
        self.primaryLanguage = primaryLanguage
        self.languageColor = languageColor
        self.defaultBranch = defaultBranch
        self.openIssueCount = openIssueCount
        self.openPullRequestCount = openPullRequestCount
        self.pushedAt = pushedAt
        self.updatedAt = updatedAt
        self.provider = provider
    }

    public var sourceProvider: RepositoryProvider {
        provider ?? RepositoryProvider.infer(from: url)
    }
}

public struct RepositoryTracking: Codable, Hashable, Sendable {
    public var repositoryID: String
    public var status: WorkStatus
    public var priority: WorkPriority
    public var progress: Int
    public var nextAction: String
    public var notes: String
    public var isFocused: Bool
    public var focusOrder: Int
    public var deadline: Date?
    public var localPath: String?
    public var gitStatus: LocalGitStatus?
    public var usesOutlinePlan: Bool?
    public var planItems: [RepositoryPlanItem]?
    public var manualProgress: Int?
    public var cloneSourceURL: String?
    public var focusBranch: String?
    public var localBranches: [String]?
    public var branchTrackings: [RepositoryBranchTracking]?
    public var modifiedAt: Date

    public init(
        repositoryID: String,
        status: WorkStatus = .inbox,
        priority: WorkPriority = .medium,
        progress: Int = 0,
        nextAction: String = "",
        notes: String = "",
        isFocused: Bool = false,
        focusOrder: Int = 0,
        deadline: Date? = nil,
        localPath: String? = nil,
        gitStatus: LocalGitStatus? = nil,
        usesOutlinePlan: Bool? = nil,
        planItems: [RepositoryPlanItem]? = nil,
        manualProgress: Int? = nil,
        cloneSourceURL: String? = nil,
        focusBranch: String? = nil,
        localBranches: [String]? = nil,
        branchTrackings: [RepositoryBranchTracking]? = nil,
        modifiedAt: Date = .now
    ) {
        self.repositoryID = repositoryID
        self.status = status
        self.priority = priority
        self.progress = min(max(progress, 0), 100)
        self.nextAction = nextAction
        self.notes = notes
        self.isFocused = isFocused
        self.focusOrder = focusOrder
        self.deadline = deadline
        self.localPath = localPath
        self.gitStatus = gitStatus
        self.usesOutlinePlan = usesOutlinePlan
        self.planItems = planItems
        self.manualProgress = manualProgress
        self.cloneSourceURL = cloneSourceURL
        self.focusBranch = focusBranch
        self.localBranches = localBranches
        self.branchTrackings = branchTrackings
        self.modifiedAt = modifiedAt
    }
}

public struct RepositoryRecord: Codable, Hashable, Identifiable, Sendable {
    public var github: GitHubRepository
    public var tracking: RepositoryTracking

    public var id: String { github.id }

    public var displayProgress: Int {
        guard tracking.usesOutlinePlan == true else {
            return tracking.progress
        }
        let items = tracking.planItems ?? []
        guard !items.isEmpty else { return 0 }
        let completed = items.filter(\.isCompleted).count
        return Int((Double(completed) / Double(items.count) * 100).rounded())
    }

    public var planCompletionSummary: (completed: Int, total: Int) {
        let items = tracking.planItems ?? []
        return (items.filter(\.isCompleted).count, items.count)
    }

    public init(github: GitHubRepository, tracking: RepositoryTracking? = nil) {
        self.github = github
        self.tracking = tracking ?? RepositoryTracking(repositoryID: github.id)
    }

    public var daysSinceLastPush: Int? {
        guard let pushedAt = github.pushedAt else { return nil }
        return Calendar.current.dateComponents([.day], from: pushedAt, to: .now).day
    }

    public var isOverdue: Bool {
        guard let deadline = tracking.deadline, tracking.status != .done else { return false }
        return deadline < Calendar.current.startOfDay(for: .now)
    }

    public var needsAttention: Bool {
        tracking.status == .blocked || isOverdue || ((daysSinceLastPush ?? 0) >= 21 && tracking.isFocused)
    }
}

public enum RepositoryReminderReason: String, Hashable, Sendable {
    case overdue
    case dueToday
    case blocked
    case conflicts
}

public struct RepositoryReminderItem: Hashable, Identifiable, Sendable {
    public let repositoryID: String
    public let repositoryName: String
    public let branchName: String?
    public let nextAction: String
    public let reasons: [RepositoryReminderReason]
    public let priority: WorkPriority
    public let focusOrder: Int

    public var id: String { repositoryID }

    public init(
        repositoryID: String,
        repositoryName: String,
        branchName: String?,
        nextAction: String,
        reasons: [RepositoryReminderReason],
        priority: WorkPriority,
        focusOrder: Int
    ) {
        self.repositoryID = repositoryID
        self.repositoryName = repositoryName
        self.branchName = branchName
        self.nextAction = nextAction
        self.reasons = reasons
        self.priority = priority
        self.focusOrder = focusOrder
    }
}

public struct RepositoryDatabase: Codable, Sendable {
    public var version: Int
    public var repositories: [RepositoryRecord]
    public var lastSyncAt: Date?
    public var activitySnapshots: [DailyActivitySnapshot]?

    public init(
        version: Int = 1,
        repositories: [RepositoryRecord],
        lastSyncAt: Date? = nil,
        activitySnapshots: [DailyActivitySnapshot]? = nil
    ) {
        self.version = version
        self.repositories = repositories
        self.lastSyncAt = lastSyncAt
        self.activitySnapshots = activitySnapshots
    }
}
