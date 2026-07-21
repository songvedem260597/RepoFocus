import Foundation
@testable import RepoFocusCore
import Testing

@Suite("Local Git operations")
struct LocalGitOperationsTests {
    @Test("Commit all stages every change and creates a commit")
    func commitsAllChanges() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let git = LocalGitOperator()

        try write("first\n", to: repository.appendingPathComponent("README.md"))
        _ = try git.commitAll(path: repository.path, message: "feat: initial project")

        #expect(try runGit(["log", "-1", "--pretty=%s"], at: repository) == "feat: initial project")
        #expect(try runGit(["status", "--porcelain"], at: repository).isEmpty)

        do {
            _ = try git.commitAll(path: repository.path, message: "nothing")
            Issue.record("Committing a clean repository should fail")
        } catch let error as LocalGitOperationError {
            #expect(error == .noChangesToCommit)
        }
    }

    @Test("Switch, merge and revert keep history recoverable")
    func switchesMergesAndReverts() throws {
        let repository = try repositoryWithInitialCommit()
        defer { try? FileManager.default.removeItem(at: repository) }
        let git = LocalGitOperator()

        _ = try runGit(["switch", "-c", "feature/workspace"], at: repository)
        try write("feature\n", to: repository.appendingPathComponent("feature.txt"))
        _ = try git.commitAll(path: repository.path, message: "feat: add workspace")
        let featureSHA = try runGit(["rev-parse", "HEAD"], at: repository)

        _ = try git.switchBranch(path: repository.path, branch: "main")
        _ = try git.merge(path: repository.path, branch: "feature/workspace")
        #expect(try String(contentsOf: repository.appendingPathComponent("feature.txt"), encoding: .utf8) == "feature\n")

        _ = try git.revert(path: repository.path, sha: featureSHA)
        #expect(!FileManager.default.fileExists(atPath: repository.appendingPathComponent("feature.txt").path))
        #expect(try runGit(["log", "-1", "--pretty=%s"], at: repository).hasPrefix("Revert"))
    }

    @Test("Merge conflicts can keep current content and continue")
    func resolvesMergeConflict() throws {
        let repository = try repositoryWithInitialCommit(contents: "base\n")
        defer { try? FileManager.default.removeItem(at: repository) }
        let git = LocalGitOperator()
        let file = repository.appendingPathComponent("shared.txt")

        _ = try runGit(["switch", "-c", "feature/conflict"], at: repository)
        try write("incoming\n", to: file)
        _ = try git.commitAll(path: repository.path, message: "feat: incoming version")

        _ = try git.switchBranch(path: repository.path, branch: "main")
        try write("current\n", to: file)
        _ = try git.commitAll(path: repository.path, message: "feat: current version")

        do {
            _ = try git.merge(path: repository.path, branch: "feature/conflict")
            Issue.record("The merge should report a conflict")
        } catch {
            // The conflict is the expected result under test.
        }

        #expect(try git.sequenceState(path: repository.path) == .merge)
        #expect(try git.conflictedFiles(path: repository.path) == [LocalGitConflictFile(path: "shared.txt")])

        _ = try git.resolveConflict(path: repository.path, file: "shared.txt", choice: .ours)
        #expect(try git.conflictedFiles(path: repository.path).isEmpty)
        #expect(try String(contentsOf: file, encoding: .utf8) == "current\n")

        _ = try git.continueOperation(path: repository.path, state: .merge)
        #expect(try git.sequenceState(path: repository.path) == .none)
        #expect(try runGit(["status", "--porcelain"], at: repository).isEmpty)
        #expect(try runGit(["rev-list", "--parents", "-n", "1", "HEAD"], at: repository).split(separator: " ").count == 3)
    }

    @Test("Push creates upstream and pull only fast-forwards")
    func pushesAndPulls() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RepoFocus-git-\(UUID().uuidString)", isDirectory: true)
        let remote = root.appendingPathComponent("remote.git", isDirectory: true)
        let first = root.appendingPathComponent("first", isDirectory: true)
        let second = root.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try runGitWithoutRepository(["init", "--bare", remote.path])
        _ = try runGit(["symbolic-ref", "HEAD", "refs/heads/main"], at: remote)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        _ = try runGit(["init", "-b", "main"], at: first)
        try configureIdentity(first)
        try write("one\n", to: first.appendingPathComponent("sync.txt"))
        _ = try LocalGitOperator().commitAll(path: first.path, message: "feat: first")
        _ = try runGit(["remote", "add", "origin", remote.path], at: first)

        _ = try LocalGitOperator().push(path: first.path)
        #expect(try runGit(["rev-parse", "--abbrev-ref", "@{upstream}"], at: first) == "origin/main")

        _ = try runGitWithoutRepository(["clone", remote.path, second.path])
        try configureIdentity(second)
        try write("two\n", to: second.appendingPathComponent("sync.txt"))
        _ = try LocalGitOperator().commitAll(path: second.path, message: "feat: second")
        _ = try LocalGitOperator().push(path: second.path)

        _ = try LocalGitOperator().pull(path: first.path)
        #expect(try String(contentsOf: first.appendingPathComponent("sync.txt"), encoding: .utf8) == "two\n")
        #expect(try runGit(["status", "--porcelain"], at: first).isEmpty)
    }

    private func repositoryWithInitialCommit(contents: String = "initial\n") throws -> URL {
        let repository = try makeRepository()
        try write(contents, to: repository.appendingPathComponent("shared.txt"))
        _ = try LocalGitOperator().commitAll(path: repository.path, message: "chore: initial")
        return repository
    }

    private func makeRepository() throws -> URL {
        let repository = FileManager.default.temporaryDirectory
            .appendingPathComponent("RepoFocus-git-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        _ = try runGit(["init", "-b", "main"], at: repository)
        try configureIdentity(repository)
        return repository
    }

    private func configureIdentity(_ repository: URL) throws {
        _ = try runGit(["config", "user.name", "RepoFocus Tests"], at: repository)
        _ = try runGit(["config", "user.email", "repofocus-tests@example.com"], at: repository)
    }

    private func write(_ value: String, to url: URL) throws {
        try value.write(to: url, atomically: true, encoding: .utf8)
    }

    private func runGit(_ arguments: [String], at repository: URL) throws -> String {
        try runGitWithoutRepository(["-C", repository.path] + arguments)
    }

    private func runGitWithoutRepository(_ arguments: [String]) throws -> String {
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
        let output = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let error = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        guard process.terminationStatus == 0 else {
            throw TestGitError.commandFailed(error.isEmpty ? output : error)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum TestGitError: Error {
    case commandFailed(String)
}
