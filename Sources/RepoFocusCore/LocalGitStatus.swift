import Foundation

public struct LocalGitStatus: Codable, Hashable, Sendable {
    public let branch: String?
    public let hasUpstream: Bool
    public let aheadCount: Int
    public let behindCount: Int
    public let changedFileCount: Int
    public let conflictCount: Int
    public let checkedAt: Date

    public init(
        branch: String? = nil,
        hasUpstream: Bool = false,
        aheadCount: Int = 0,
        behindCount: Int = 0,
        changedFileCount: Int = 0,
        conflictCount: Int = 0,
        checkedAt: Date = .now
    ) {
        self.branch = branch
        self.hasUpstream = hasUpstream
        self.aheadCount = max(aheadCount, 0)
        self.behindCount = max(behindCount, 0)
        self.changedFileCount = max(changedFileCount, 0)
        self.conflictCount = max(conflictCount, 0)
        self.checkedAt = checkedAt
    }

    public var hasUncommittedChanges: Bool { changedFileCount > 0 }
    public var hasUnpushedCommits: Bool { aheadCount > 0 }
    public var hasConflicts: Bool { conflictCount > 0 }

    public var isCleanAndSynced: Bool {
        hasUpstream && !hasUncommittedChanges && !hasUnpushedCommits && behindCount == 0
    }
}

public struct LocalGitCommit: Hashable, Sendable {
    public let sha: String
    public let subject: String
    public let committedAt: Date

    public init(sha: String, subject: String, committedAt: Date) {
        self.sha = sha
        self.subject = subject
        self.committedAt = committedAt
    }
}

public protocol LocalGitStatusChecking: Sendable {
    func check(path: String) throws -> LocalGitStatus
    func recentCommits(path: String, limit: Int) throws -> [LocalGitCommit]
    func recentCommits(path: String, branch: String?, limit: Int) throws -> [LocalGitCommit]
    func branches(path: String) throws -> [String]
}

public extension LocalGitStatusChecking {
    func recentCommits(path: String, limit: Int) throws -> [LocalGitCommit] {
        []
    }

    func recentCommits(path: String, branch: String?, limit: Int) throws -> [LocalGitCommit] {
        try recentCommits(path: path, limit: limit)
    }

    func branches(path: String) throws -> [String] {
        []
    }
}

public enum LocalGitStatusError: LocalizedError, Equatable {
    case emptyPath
    case folderNotFound
    case notARepository
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyPath:
            "Đường dẫn repo đang trống."
        case .folderNotFound:
            "Không tìm thấy thư mục này trên máy."
        case .notARepository:
            "Thư mục này không phải là một Git repository."
        case let .commandFailed(message):
            message.isEmpty ? "Không thể đọc trạng thái Git." : message
        }
    }
}

public struct LocalGitStatusChecker: LocalGitStatusChecking {
    public init() {}

    public func check(path: String) throws -> LocalGitStatus {
        let normalizedPath = Self.normalized(path)
        guard !normalizedPath.isEmpty else { throw LocalGitStatusError.emptyPath }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalizedPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw LocalGitStatusError.folderNotFound
        }

        let result = try runGit(
            arguments: ["-C", normalizedPath, "status", "--porcelain=v2", "--branch"]
        )

        guard result.exitCode == 0 else {
            let message = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
            if message.localizedCaseInsensitiveContains("not a git repository") {
                throw LocalGitStatusError.notARepository
            }
            throw LocalGitStatusError.commandFailed(message)
        }

        return Self.parsePorcelainV2(result.output)
    }

    public func recentCommits(path: String, limit: Int = 100) throws -> [LocalGitCommit] {
        try recentCommits(path: path, branch: nil, limit: limit)
    }

    public func recentCommits(
        path: String,
        branch: String?,
        limit: Int = 100
    ) throws -> [LocalGitCommit] {
        let normalizedPath = Self.normalized(path)
        guard !normalizedPath.isEmpty else { throw LocalGitStatusError.emptyPath }

        var arguments = [
            "-C", normalizedPath,
            "log", "-n", "\(max(limit, 1))"
        ]
        if let branch, !branch.isEmpty {
            arguments.append(branch)
        }
        arguments.append("--pretty=format:%H%x09%ct%x09%s")
        let result = try runGit(arguments: arguments)

        guard result.exitCode == 0 else {
            let message = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
            if message.localizedCaseInsensitiveContains("does not have any commits yet") ||
                message.localizedCaseInsensitiveContains("your current branch") {
                return []
            }
            if message.localizedCaseInsensitiveContains("not a git repository") {
                throw LocalGitStatusError.notARepository
            }
            throw LocalGitStatusError.commandFailed(message)
        }

        return Self.parseLog(result.output)
    }

    public func branches(path: String) throws -> [String] {
        let normalizedPath = Self.normalized(path)
        guard !normalizedPath.isEmpty else { throw LocalGitStatusError.emptyPath }

        let result = try runGit(arguments: [
            "-C", normalizedPath,
            "for-each-ref", "--format=%(refname:short)",
            "refs/heads", "refs/remotes/origin"
        ])
        guard result.exitCode == 0 else {
            throw LocalGitStatusError.commandFailed(
                result.error.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return result.output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { $0 != "origin/HEAD" }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func parsePorcelainV2(
        _ output: String,
        checkedAt: Date = .now
    ) -> LocalGitStatus {
        var branch: String?
        var hasUpstream = false
        var aheadCount = 0
        var behindCount = 0
        var changedFileCount = 0
        var conflictCount = 0

        for line in output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            if line.hasPrefix("# branch.head ") {
                let value = String(line.dropFirst("# branch.head ".count))
                branch = value == "(detached)" ? nil : value
            } else if line.hasPrefix("# branch.upstream ") {
                hasUpstream = true
            } else if line.hasPrefix("# branch.ab ") {
                let values = line.split(separator: " ")
                for value in values {
                    if value.hasPrefix("+") {
                        aheadCount = Int(value.dropFirst()) ?? 0
                    } else if value.hasPrefix("-") {
                        behindCount = Int(value.dropFirst()) ?? 0
                    }
                }
            } else if line.hasPrefix("u ") {
                changedFileCount += 1
                conflictCount += 1
            } else if line.hasPrefix("1 ") || line.hasPrefix("2 ") || line.hasPrefix("? ") {
                changedFileCount += 1
            }
        }

        return LocalGitStatus(
            branch: branch,
            hasUpstream: hasUpstream,
            aheadCount: aheadCount,
            behindCount: behindCount,
            changedFileCount: changedFileCount,
            conflictCount: conflictCount,
            checkedAt: checkedAt
        )
    }

    static func parseLog(_ output: String) -> [LocalGitCommit] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                guard fields.count == 3,
                      let timestamp = TimeInterval(fields[1]) else {
                    return nil
                }
                return LocalGitCommit(
                    sha: String(fields[0]),
                    subject: String(fields[2]),
                    committedAt: Date(timeIntervalSince1970: timestamp)
                )
            }
    }

    private static func normalized(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return NSString(string: trimmed).expandingTildeInPath
    }

    private func runGit(arguments: [String]) throws -> (output: String, error: String, exitCode: Int32) {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C"]) { _, new in new }

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (output, error, process.terminationStatus)
    }
}
