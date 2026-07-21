import Foundation
@testable import RepoFocusCore
import Testing

@Suite("Repository store")
struct RepositoryStoreTests {
    @Test("Git porcelain output reports commit, push and conflict state")
    func parsesLocalGitStatus() {
        let output = """
        # branch.oid 0123456789
        # branch.head main
        # branch.upstream origin/main
        # branch.ab +2 -1
        1 .M N... 100644 100644 100644 abc abc Sources/App.swift
        u UU N... 100644 100644 100644 100644 abc def ghi Sources/Conflict.swift
        ? Notes.md
        """

        let status = LocalGitStatusChecker.parsePorcelainV2(output)

        #expect(status.branch == "main")
        #expect(status.hasUpstream)
        #expect(status.aheadCount == 2)
        #expect(status.behindCount == 1)
        #expect(status.changedFileCount == 3)
        #expect(status.conflictCount == 1)
        #expect(status.hasUncommittedChanges)
        #expect(status.hasUnpushedCommits)
        #expect(status.hasConflicts)
    }

    @Test("Tracking changes are clamped and persisted")
    @MainActor
    func trackingUpdateIsClampedAndPersisted() throws {
        let persistence = MemoryPersistence()
        let store = RepositoryStore(
            persistence: persistence,
            tokenStore: MemoryTokenStore(),
            githubClient: StaticGitHubClient(repositories: []),
            useSampleDataWhenEmpty: true
        )

        let repositoryID = try #require(store.repositories.first?.id)
        store.updateTracking(repositoryID: repositoryID) {
            $0.progress = 140
            $0.status = .active
        }

        #expect(store.repository(id: repositoryID)?.tracking.progress == 100)
        #expect(store.repository(id: repositoryID)?.tracking.status == .active)
        #expect(persistence.database?.repositories.first?.tracking.progress == 100)
    }

    @Test("GitHub refresh preserves local tracking")
    @MainActor
    func mergePreservesLocalTracking() throws {
        let original = try #require(SampleData.repositories.first)
        let persistence = MemoryPersistence(
            database: RepositoryDatabase(repositories: [original])
        )
        let store = RepositoryStore(
            persistence: persistence,
            tokenStore: MemoryTokenStore(),
            githubClient: StaticGitHubClient(repositories: []),
            useSampleDataWhenEmpty: false
        )

        let refreshed = GitHubRepository(
            id: original.id,
            name: original.github.name,
            nameWithOwner: original.github.nameWithOwner,
            url: original.github.url,
            description: "Fresh description",
            isPrivate: true,
            primaryLanguage: "Swift",
            openIssueCount: 99,
            pushedAt: .now,
            updatedAt: .now
        )

        store.merge([refreshed])

        let result = try #require(store.repository(id: original.id))
        #expect(result.github.description == "Fresh description")
        #expect(result.github.openIssueCount == 99)
        #expect(result.tracking.progress == original.tracking.progress)
        #expect(result.tracking.nextAction == original.tracking.nextAction)
    }

    @Test("Local database round-trips without losing fields")
    func databaseRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("repositories.json")
        let persistence = JSONRepositoryPersistence(fileURL: fileURL)
        let database = RepositoryDatabase(
            repositories: SampleData.repositories,
            lastSyncAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try persistence.save(database)
        let loaded = try persistence.load()
        let decoded = try #require(loaded)

        #expect(decoded.repositories == database.repositories)
        #expect(decoded.lastSyncAt == database.lastSyncAt)

        try? FileManager.default.removeItem(at: directory)
    }
}

private final class MemoryPersistence: RepositoryPersisting, @unchecked Sendable {
    var database: RepositoryDatabase?

    init(database: RepositoryDatabase? = nil) {
        self.database = database
    }

    func load() throws -> RepositoryDatabase? {
        database
    }

    func save(_ database: RepositoryDatabase) throws {
        self.database = database
    }
}

private final class MemoryTokenStore: TokenStoring, @unchecked Sendable {
    var token: String?

    func loadToken() throws -> String? {
        token
    }

    func saveToken(_ token: String) throws {
        self.token = token
    }

    func deleteToken() throws {
        token = nil
    }
}

private struct StaticGitHubClient: GitHubRepositoryFetching {
    let repositories: [GitHubRepository]

    func fetchRepositories(token: String) async throws -> [GitHubRepository] {
        repositories
    }
}
