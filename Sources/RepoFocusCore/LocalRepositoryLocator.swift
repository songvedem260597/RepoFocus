import Foundation

public struct RemoteRepositoryIdentity: Hashable, Sendable {
    public let provider: RepositoryProvider
    public let host: String
    public let path: String

    public init(provider: RepositoryProvider, host: String, path: String) {
        self.provider = provider
        self.host = host
        self.path = path
    }
}

public protocol LocalRepositoryLocating: Sendable {
    func locate(repositories: [GitHubRepository]) throws -> [String: String]
}

public struct LocalRepositoryLocator: LocalRepositoryLocating {
    private let roots: [URL]
    private let maximumDepth: Int

    public init(roots: [URL]? = nil, maximumDepth: Int = 7) {
        self.roots = roots ?? Self.defaultRoots
        self.maximumDepth = maximumDepth
    }

    public func locate(repositories: [GitHubRepository]) throws -> [String: String] {
        let targets = Dictionary(uniqueKeysWithValues: repositories.map {
            (Self.identityKey(provider: $0.sourceProvider, path: $0.nameWithOwner), $0.id)
        })
        let repositoriesByName = Dictionary(grouping: repositories) { $0.name.lowercased() }
        var exactNameCandidates: [String: [String]] = [:]
        var matches: [String: String] = [:]

        for localURL in discoverGitRepositories() {
            let path = localURL.standardizedFileURL.path
            if let remote = originRemote(for: localURL),
               let identity = Self.normalizedRemoteIdentity(remote),
               let repositoryID = targets[Self.identityKey(
                   provider: identity.provider,
                   path: identity.path
               )] {
                matches[repositoryID] = path
                continue
            }

            let folderName = localURL.lastPathComponent.lowercased()
            if repositoriesByName[folderName] != nil {
                exactNameCandidates[folderName, default: []].append(path)
            }
        }

        for (name, paths) in exactNameCandidates where paths.count == 1 {
            guard let repositories = repositoriesByName[name], repositories.count == 1,
                  let repository = repositories.first,
                  matches[repository.id] == nil else { continue }
            matches[repository.id] = paths[0]
        }

        return matches
    }

    static func normalizedGitHubSlug(_ remote: String) -> String? {
        guard let identity = normalizedRemoteIdentity(remote), identity.provider == .github else {
            return nil
        }
        return identity.path
    }

    static func normalizedGitLabSlug(_ remote: String) -> String? {
        guard let identity = normalizedRemoteIdentity(remote), identity.provider == .gitlab else {
            return nil
        }
        return identity.path
    }

    public static func normalizedRemoteIdentity(_ remote: String) -> RemoteRepositoryIdentity? {
        let trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let host: String
        var path: String
        if let separator = trimmed.firstIndex(of: ":"),
           !trimmed.contains("://"),
           trimmed[..<separator].contains("@") {
            let userAndHost = String(trimmed[..<separator])
            host = String(userAndHost.split(separator: "@").last ?? "").lowercased()
            path = String(trimmed[trimmed.index(after: separator)...])
        } else if let components = URLComponents(string: trimmed),
                  let parsedHost = components.host {
            host = parsedHost.lowercased()
            path = components.percentEncodedPath.removingPercentEncoding ?? components.path
        } else {
            return nil
        }

        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.lowercased().hasSuffix(".git") {
            path.removeLast(4)
        }
        guard path.split(separator: "/").count >= 2 else { return nil }

        let provider: RepositoryProvider
        switch host {
        case "github.com", "www.github.com": provider = .github
        case "gitlab.com", "www.gitlab.com": provider = .gitlab
        default: provider = .other
        }
        return RemoteRepositoryIdentity(provider: provider, host: host, path: path)
    }

    private static func identityKey(provider: RepositoryProvider, path: String) -> String {
        "\(provider.rawValue):\(path.lowercased())"
    }

    private func discoverGitRepositories() -> [URL] {
        let fileManager = FileManager.default
        var queue: [(url: URL, depth: Int)] = roots
            .map { ($0.standardizedFileURL, 0) }
            .filter { fileManager.fileExists(atPath: $0.url.path) }
        var cursor = 0
        var repositories: [URL] = []
        var visited = Set<String>()

        while cursor < queue.count {
            let current = queue[cursor]
            cursor += 1
            guard visited.insert(current.url.path).inserted else { continue }

            let gitMarker = current.url.appendingPathComponent(".git")
            if fileManager.fileExists(atPath: gitMarker.path) {
                repositories.append(current.url)
                continue
            }
            guard current.depth < maximumDepth else { continue }

            let children: [URL]
            do {
                children = try fileManager.contentsOfDirectory(
                    at: current.url,
                    includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey],
                    options: [.skipsPackageDescendants]
                )
            } catch {
                continue
            }

            for child in children {
                let name = child.lastPathComponent
                guard !Self.skippedDirectoryNames.contains(name) else { continue }
                guard !name.hasPrefix(".") else { continue }

                guard let values = try? child.resourceValues(
                    forKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]
                ), values.isDirectory == true, values.isSymbolicLink != true, values.isPackage != true else {
                    continue
                }
                queue.append((child, current.depth + 1))
            }
        }

        return repositories
    }

    private func originRemote(for repositoryURL: URL) -> String? {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repositoryURL.path, "remote", "get-url", "origin"]
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private static let skippedDirectoryNames: Set<String> = [
        "Library", "Applications", "Movies", "Music", "Pictures",
        "node_modules", "Pods", "vendor", "dist", ".build", "DerivedData"
    ]

    private static var defaultRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // Documents and Desktop are protected by macOS privacy controls. Scanning
        // them on launch would show a broad access prompt before the user has
        // chosen a folder. Those locations remain available through the explicit
        // folder picker in the repository inspector and clone flow.
        return ["Developer", "Projects", "Code", "GitHub"]
            .map { home.appendingPathComponent($0, isDirectory: true) }
    }
}
