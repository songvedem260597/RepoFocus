import Foundation
import Security

public protocol RepositoryPersisting: Sendable {
    func load() throws -> RepositoryDatabase?
    func save(_ database: RepositoryDatabase) throws
}

public final class JSONRepositoryPersistence: RepositoryPersisting, @unchecked Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func live() -> JSONRepositoryPersistence {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        return JSONRepositoryPersistence(
            fileURL: applicationSupport
                .appendingPathComponent("RepoFocus", isDirectory: true)
                .appendingPathComponent("repositories.json")
        )
    }

    public func load() throws -> RepositoryDatabase? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try Self.decoder.decode(RepositoryDatabase.self, from: data)
    }

    public func save(_ database: RepositoryDatabase) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let data = try Self.encoder.encode(database)
        try data.write(to: fileURL, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }()
}

public protocol TokenStoring: Sendable {
    func loadToken() throws -> String?
    func saveToken(_ token: String) throws
    func deleteToken() throws
}

public protocol TokenConnectionControlling: Sendable {
    func setConnectionEnabled(_ enabled: Bool) throws
}

public enum GitHubCLITokenError: LocalizedError {
    case unavailable
    case managedByCLI

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "GitHub CLI chưa đăng nhập. Hãy chạy `gh auth login` trước."
        case .managedByCLI:
            "RepoFocus sử dụng phiên đăng nhập của GitHub CLI và không lưu token riêng."
        }
    }
}

public final class GitHubCLITokenStore: TokenStoring, TokenConnectionControlling, @unchecked Sendable {
    private let defaults: UserDefaults
    private let disabledKey: String

    public init(
        defaults: UserDefaults = .standard,
        disabledKey: String = "github.cli-connection-disabled"
    ) {
        self.defaults = defaults
        self.disabledKey = disabledKey
    }

    public func loadToken() throws -> String? {
        guard !defaults.bool(forKey: disabledKey) else { return nil }
        guard let executableURL = Self.executableURL else {
            throw GitHubCLITokenError.unavailable
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = ["auth", "token"]
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C"]) { _, new in new }

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitHubCLITokenError.unavailable
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let token = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token, !token.isEmpty else {
            throw GitHubCLITokenError.unavailable
        }
        return token
    }

    public func saveToken(_ token: String) throws {
        throw GitHubCLITokenError.managedByCLI
    }

    public func deleteToken() throws {
        try setConnectionEnabled(false)
    }

    public func setConnectionEnabled(_ enabled: Bool) throws {
        defaults.set(!enabled, forKey: disabledKey)
    }

    private static var executableURL: URL? {
        [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh"
        ]
        .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        .map { URL(fileURLWithPath: $0) }
    }
}

public enum KeychainError: LocalizedError {
    case status(OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .status(let status):
            return SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        case .invalidData:
            return "The GitHub token in Keychain is not valid UTF-8 data."
        }
    }
}

public struct KeychainTokenStore: TokenStoring, Sendable {
    private let service: String
    private let account: String

    public init(
        service: String = "com.repofocus.github-token",
        account: String = "default"
    ) {
        self.service = service
        self.account = account
    }

    public func loadToken() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return token
    }

    public func saveToken(_ token: String) throws {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = Data(normalized.utf8)
        let update = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)

        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainError.status(updateStatus) }

        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
    }

    public func deleteToken() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
