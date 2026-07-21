import Foundation

public struct LocalRepositoryCloneResult: Equatable, Sendable {
    public let path: String
    public let folderName: String

    public init(path: String, folderName: String) {
        self.path = path
        self.folderName = folderName
    }
}

public protocol LocalRepositoryCloning: Sendable {
    func clone(remoteURL: String, destinationParent: String) throws -> LocalRepositoryCloneResult
}

public enum LocalRepositoryCloneError: LocalizedError, Equatable {
    case emptyRemoteURL
    case invalidRemoteURL
    case emptyDestination
    case destinationNotFound
    case destinationIsNotDirectory
    case destinationAlreadyExists(String)
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyRemoteURL:
            "URL Git đang trống."
        case .invalidRemoteURL:
            "Không thể xác định tên repo từ URL này."
        case .emptyDestination:
            "Chưa chọn thư mục lưu repo."
        case .destinationNotFound:
            "Không tìm thấy thư mục đích trên máy."
        case .destinationIsNotDirectory:
            "Vị trí đã chọn không phải là một thư mục."
        case let .destinationAlreadyExists(path):
            "Thư mục đích đã tồn tại: \(path)"
        case let .commandFailed(message):
            message.isEmpty ? "Không thể clone repository." : message
        }
    }
}

public struct LocalRepositoryCloner: LocalRepositoryCloning {
    public init() {}

    public func clone(
        remoteURL: String,
        destinationParent: String
    ) throws -> LocalRepositoryCloneResult {
        let normalizedRemote = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRemote.isEmpty else { throw LocalRepositoryCloneError.emptyRemoteURL }
        guard Self.isSupportedRemote(normalizedRemote) else {
            throw LocalRepositoryCloneError.invalidRemoteURL
        }

        let folderName = try Self.folderName(from: normalizedRemote)
        let parentPath = Self.normalizedPath(destinationParent)
        guard !parentPath.isEmpty else { throw LocalRepositoryCloneError.emptyDestination }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parentPath, isDirectory: &isDirectory) else {
            throw LocalRepositoryCloneError.destinationNotFound
        }
        guard isDirectory.boolValue else {
            throw LocalRepositoryCloneError.destinationIsNotDirectory
        }

        let destinationURL = URL(fileURLWithPath: parentPath, isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw LocalRepositoryCloneError.destinationAlreadyExists(destinationURL.path)
        }

        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "clone", "--progress", "--",
            normalizedRemote,
            destinationURL.path
        ]
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.environment = ProcessInfo.processInfo.environment.merging([
            "LC_ALL": "C",
            "GIT_TERMINAL_PROMPT": "0"
        ]) { _, new in new }

        do {
            try process.run()
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: outputData, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                try? FileManager.default.removeItem(at: destinationURL)
                let safeMessage = output
                    .replacingOccurrences(of: normalizedRemote, with: "remote repository")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw LocalRepositoryCloneError.commandFailed(safeMessage)
            }
        } catch let error as LocalRepositoryCloneError {
            throw error
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw LocalRepositoryCloneError.commandFailed(error.localizedDescription)
        }

        return LocalRepositoryCloneResult(
            path: destinationURL.path,
            folderName: folderName
        )
    }

    public static func folderName(from remoteURL: String) throws -> String {
        var value = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") {
            value.removeLast()
        }
        if value.lowercased().hasSuffix(".git") {
            value.removeLast(4)
        }

        let slashComponent = value.split(separator: "/").last.map(String.init) ?? ""
        let colonComponent = slashComponent.split(separator: ":").last.map(String.init) ?? ""
        let forbidden = CharacterSet(charactersIn: "/:\\")
        let folderName = colonComponent
            .components(separatedBy: forbidden)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !folderName.isEmpty, folderName != ".", folderName != ".." else {
            throw LocalRepositoryCloneError.invalidRemoteURL
        }
        return folderName
    }

    private static func normalizedPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return NSString(string: trimmed).expandingTildeInPath
    }

    private static func isSupportedRemote(_ value: String) -> Bool {
        if value.hasPrefix("/") || value.hasPrefix("~/") || value.hasPrefix("./") || value.hasPrefix("../") {
            return true
        }
        if value.contains("@"),
           let colon = value.firstIndex(of: ":"),
           !value[..<colon].contains("/") {
            return true
        }
        guard let scheme = URLComponents(string: value)?.scheme?.lowercased() else {
            return false
        }
        return ["https", "http", "ssh", "git", "file"].contains(scheme)
    }
}
