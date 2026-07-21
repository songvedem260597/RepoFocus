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
        updatedAt: Date = .now
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
    }
}

public struct RepositoryTracking: Codable, Hashable, Sendable {
    public let repositoryID: String
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
        self.modifiedAt = modifiedAt
    }
}

public struct RepositoryRecord: Codable, Hashable, Identifiable, Sendable {
    public var github: GitHubRepository
    public var tracking: RepositoryTracking

    public var id: String { github.id }

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

public struct RepositoryDatabase: Codable, Sendable {
    public var version: Int
    public var repositories: [RepositoryRecord]
    public var lastSyncAt: Date?

    public init(version: Int = 1, repositories: [RepositoryRecord], lastSyncAt: Date? = nil) {
        self.version = version
        self.repositories = repositories
        self.lastSyncAt = lastSyncAt
    }
}
