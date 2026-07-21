import Foundation

public enum LocalGitOperationKind: String, Equatable, Sendable {
    case switchBranch
    case commit
    case pull
    case push
    case revert
    case merge
    case resolveConflict
    case continueOperation
    case abortOperation
}

public enum LocalGitSequenceState: String, Equatable, Sendable {
    case none
    case merge
    case revert
}

public enum LocalGitConflictChoice: Equatable, Sendable {
    case ours
    case theirs
    case markResolved
}

public struct LocalGitConflictFile: Hashable, Identifiable, Sendable {
    public let path: String

    public init(path: String) {
        self.path = path
    }

    public var id: String { path }
}

public struct LocalGitOperationResult: Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public enum LocalGitOperationError: LocalizedError, Equatable {
    case emptyPath
    case folderNotFound
    case notARepository
    case invalidBranch
    case invalidCommitMessage
    case invalidCommit
    case noChangesToCommit
    case noRemote
    case noOperationInProgress
    case conflictFileNotFound
    case unresolvedConflicts
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyPath:
            "Đường dẫn repo đang trống."
        case .folderNotFound:
            "Không tìm thấy thư mục repo trên máy."
        case .notARepository:
            "Thư mục này không phải là một Git repository."
        case .invalidBranch:
            "Tên branch không hợp lệ."
        case .invalidCommitMessage:
            "Hãy nhập nội dung commit."
        case .invalidCommit:
            "Mã commit không hợp lệ."
        case .noChangesToCommit:
            "Không có thay đổi nào để commit."
        case .noRemote:
            "Repo chưa có remote origin để push."
        case .noOperationInProgress:
            "Không có merge hoặc revert nào đang chờ xử lý."
        case .conflictFileNotFound:
            "File này không còn nằm trong danh sách conflict."
        case .unresolvedConflicts:
            "Hãy xử lý hết file conflict trước khi tiếp tục."
        case let .commandFailed(message):
            message.isEmpty ? "Thao tác Git không thành công." : message
        }
    }
}

public protocol LocalGitOperating: Sendable {
    func switchBranch(path: String, branch: String) throws -> LocalGitOperationResult
    func commitAll(path: String, message: String) throws -> LocalGitOperationResult
    func pull(path: String) throws -> LocalGitOperationResult
    func push(path: String) throws -> LocalGitOperationResult
    func revert(path: String, sha: String) throws -> LocalGitOperationResult
    func merge(path: String, branch: String) throws -> LocalGitOperationResult
    func conflictedFiles(path: String) throws -> [LocalGitConflictFile]
    func sequenceState(path: String) throws -> LocalGitSequenceState
    func resolveConflict(path: String, file: String, choice: LocalGitConflictChoice) throws -> LocalGitOperationResult
    func continueOperation(path: String, state: LocalGitSequenceState) throws -> LocalGitOperationResult
    func abortOperation(path: String, state: LocalGitSequenceState) throws -> LocalGitOperationResult
}

public struct LocalGitOperator: LocalGitOperating {
    public init() {}

    public func switchBranch(path: String, branch: String) throws -> LocalGitOperationResult {
        let repositoryPath = try validatedRepositoryPath(path)
        let branch = try validatedBranch(branch)
        let arguments: [String]
        if branch.hasPrefix("origin/") {
            arguments = ["-C", repositoryPath, "switch", "--track", branch]
        } else {
            arguments = ["-C", repositoryPath, "switch", "--", branch]
        }
        let result = try requireSuccess(arguments)
        return LocalGitOperationResult(message: usefulMessage(result, fallback: "Đã chuyển sang branch \(branch)."))
    }

    public func commitAll(path: String, message: String) throws -> LocalGitOperationResult {
        let repositoryPath = try validatedRepositoryPath(path)
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { throw LocalGitOperationError.invalidCommitMessage }

        _ = try requireSuccess(["-C", repositoryPath, "add", "-A"])
        let staged = try runGit(["-C", repositoryPath, "diff", "--cached", "--quiet"])
        if staged.exitCode == 0 {
            throw LocalGitOperationError.noChangesToCommit
        }
        guard staged.exitCode == 1 else { throw commandError(staged) }

        let result = try requireSuccess(["-C", repositoryPath, "commit", "-m", message])
        return LocalGitOperationResult(message: usefulMessage(result, fallback: "Đã tạo commit mới."))
    }

    public func pull(path: String) throws -> LocalGitOperationResult {
        let repositoryPath = try validatedRepositoryPath(path)
        let result = try requireSuccess(["-C", repositoryPath, "pull", "--ff-only"])
        return LocalGitOperationResult(message: usefulMessage(result, fallback: "Đã pull thay đổi mới nhất."))
    }

    public func push(path: String) throws -> LocalGitOperationResult {
        let repositoryPath = try validatedRepositoryPath(path)
        let upstream = try runGit(["-C", repositoryPath, "rev-parse", "--abbrev-ref", "@{upstream}"])
        let result: GitCommandResult
        if upstream.exitCode == 0 {
            result = try requireSuccess(["-C", repositoryPath, "push"])
        } else {
            let origin = try runGit(["-C", repositoryPath, "remote", "get-url", "origin"])
            guard origin.exitCode == 0 else { throw LocalGitOperationError.noRemote }
            let branchResult = try requireSuccess(["-C", repositoryPath, "branch", "--show-current"])
            let branch = branchResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !branch.isEmpty else { throw LocalGitOperationError.invalidBranch }
            result = try requireSuccess([
                "-C", repositoryPath, "push", "--set-upstream", "origin", branch
            ])
        }
        return LocalGitOperationResult(message: usefulMessage(result, fallback: "Đã push lên remote."))
    }

    public func revert(path: String, sha: String) throws -> LocalGitOperationResult {
        let repositoryPath = try validatedRepositoryPath(path)
        let sha = sha.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sha.range(of: #"^[0-9a-fA-F]{7,40}$"#, options: .regularExpression) != nil else {
            throw LocalGitOperationError.invalidCommit
        }
        let result = try requireSuccess(["-C", repositoryPath, "revert", "--no-edit", "--", sha])
        return LocalGitOperationResult(message: usefulMessage(result, fallback: "Đã tạo commit hoàn tác \(sha.prefix(7))."))
    }

    public func merge(path: String, branch: String) throws -> LocalGitOperationResult {
        let repositoryPath = try validatedRepositoryPath(path)
        let branch = try validatedBranch(branch)
        let result = try requireSuccess(["-C", repositoryPath, "merge", "--no-edit", "--", branch])
        return LocalGitOperationResult(message: usefulMessage(result, fallback: "Đã merge branch \(branch)."))
    }

    public func conflictedFiles(path: String) throws -> [LocalGitConflictFile] {
        let repositoryPath = try validatedRepositoryPath(path)
        let result = try requireSuccess([
            "-C", repositoryPath, "diff", "--name-only", "--diff-filter=U", "-z"
        ])
        return result.output
            .split(separator: "\0", omittingEmptySubsequences: true)
            .map { LocalGitConflictFile(path: String($0)) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    public func sequenceState(path: String) throws -> LocalGitSequenceState {
        let repositoryPath = try validatedRepositoryPath(path)
        let result = try requireSuccess(["-C", repositoryPath, "rev-parse", "--absolute-git-dir"])
        let gitDirectory = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: URL(fileURLWithPath: gitDirectory).appendingPathComponent("MERGE_HEAD").path) {
            return .merge
        }
        if fileManager.fileExists(atPath: URL(fileURLWithPath: gitDirectory).appendingPathComponent("REVERT_HEAD").path) {
            return .revert
        }
        let sequencer = URL(fileURLWithPath: gitDirectory).appendingPathComponent("sequencer/todo").path
        if let contents = try? String(contentsOfFile: sequencer, encoding: .utf8),
           contents.split(separator: "\n").contains(where: { $0.hasPrefix("revert ") }) {
            return .revert
        }
        return .none
    }

    public func resolveConflict(
        path: String,
        file: String,
        choice: LocalGitConflictChoice
    ) throws -> LocalGitOperationResult {
        let repositoryPath = try validatedRepositoryPath(path)
        guard try conflictedFiles(path: repositoryPath).contains(where: { $0.path == file }) else {
            throw LocalGitOperationError.conflictFileNotFound
        }

        switch choice {
        case .ours:
            _ = try requireSuccess(["-C", repositoryPath, "checkout", "--ours", "--", file])
        case .theirs:
            _ = try requireSuccess(["-C", repositoryPath, "checkout", "--theirs", "--", file])
        case .markResolved:
            break
        }
        _ = try requireSuccess(["-C", repositoryPath, "add", "--", file])
        return LocalGitOperationResult(message: "Đã đánh dấu \(file) là đã xử lý.")
    }

    public func continueOperation(
        path: String,
        state: LocalGitSequenceState
    ) throws -> LocalGitOperationResult {
        let repositoryPath = try validatedRepositoryPath(path)
        guard try conflictedFiles(path: repositoryPath).isEmpty else {
            throw LocalGitOperationError.unresolvedConflicts
        }
        let result: GitCommandResult
        switch state {
        case .merge:
            result = try requireSuccess(["-C", repositoryPath, "-c", "core.editor=true", "merge", "--continue"])
        case .revert:
            result = try requireSuccess(["-C", repositoryPath, "-c", "core.editor=true", "revert", "--continue"])
        case .none:
            throw LocalGitOperationError.noOperationInProgress
        }
        return LocalGitOperationResult(message: usefulMessage(result, fallback: "Đã hoàn tất thao tác Git."))
    }

    public func abortOperation(
        path: String,
        state: LocalGitSequenceState
    ) throws -> LocalGitOperationResult {
        let repositoryPath = try validatedRepositoryPath(path)
        let result: GitCommandResult
        switch state {
        case .merge:
            result = try requireSuccess(["-C", repositoryPath, "merge", "--abort"])
        case .revert:
            result = try requireSuccess(["-C", repositoryPath, "revert", "--abort"])
        case .none:
            throw LocalGitOperationError.noOperationInProgress
        }
        return LocalGitOperationResult(message: usefulMessage(result, fallback: "Đã hủy thao tác Git."))
    }

    private func validatedRepositoryPath(_ path: String) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LocalGitOperationError.emptyPath }
        let expanded = NSString(string: trimmed).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw LocalGitOperationError.folderNotFound
        }
        let result = try runGit(["-C", expanded, "rev-parse", "--is-inside-work-tree"])
        guard result.exitCode == 0,
              result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            throw LocalGitOperationError.notARepository
        }
        return expanded
    }

    private func validatedBranch(_ branch: String) throws -> String {
        let normalized = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !normalized.hasPrefix("-") else {
            throw LocalGitOperationError.invalidBranch
        }
        let result = try runGit(["check-ref-format", "--branch", normalized])
        guard result.exitCode == 0 else { throw LocalGitOperationError.invalidBranch }
        return normalized
    }

    private func requireSuccess(_ arguments: [String]) throws -> GitCommandResult {
        let result = try runGit(arguments)
        guard result.exitCode == 0 else { throw commandError(result) }
        return result
    }

    private func commandError(_ result: GitCommandResult) -> LocalGitOperationError {
        let message = [result.error, result.output]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        if message.localizedCaseInsensitiveContains("not a git repository") {
            return .notARepository
        }
        return .commandFailed(message)
    }

    private func usefulMessage(_ result: GitCommandResult, fallback: String) -> String {
        let message = [result.output, result.error]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        return message.isEmpty ? fallback : message
    }

    private func runGit(_ arguments: [String]) throws -> GitCommandResult {
        let process = Process()
        let combinedPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardOutput = combinedPipe
        process.standardError = combinedPipe
        process.environment = ProcessInfo.processInfo.environment.merging([
            "LC_ALL": "C",
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_SSH_COMMAND": "ssh -oBatchMode=yes"
        ]) { _, new in new }

        try process.run()
        let data = combinedPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return GitCommandResult(output: output, error: "", exitCode: process.terminationStatus)
    }
}

private struct GitCommandResult {
    let output: String
    let error: String
    let exitCode: Int32
}
