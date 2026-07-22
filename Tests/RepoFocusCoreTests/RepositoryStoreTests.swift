import Foundation
@testable import RepoFocusCore
import Testing

@Suite("Repository store")
struct RepositoryStoreTests {
    @Test("GitHub push events preserve exact totals and branch names")
    func parsesGitHubPushEvents() throws {
        let data = Data(#"""
        [
          {
            "id": "push-1",
            "type": "PushEvent",
            "repo": { "name": "songvedem260597/RepoFocus" },
            "payload": {
              "ref": "refs/heads/feature/activity",
              "size": 3,
              "distinct_size": 2,
              "commits": [
                { "sha": "abcdef123456", "message": "feat: thêm thống kê theo ngày", "url": "https://api.github.com/commits/abcdef" },
                { "sha": "123456abcdef", "message": "fix: sửa bộ lọc branch", "url": "https://api.github.com/commits/123456" }
              ]
            },
            "created_at": "2026-07-21T04:30:00Z"
          },
          {
            "id": "issue-1",
            "type": "IssuesEvent",
            "repo": { "name": "songvedem260597/RepoFocus" },
            "payload": {},
            "created_at": "2026-07-21T05:00:00Z"
          },
          {
            "id": "push-tag",
            "type": "PushEvent",
            "repo": { "name": "songvedem260597/RepoFocus" },
            "payload": { "ref": "refs/tags/v0.7.0", "size": 1 },
            "created_at": "2026-07-21T06:00:00Z"
          }
        ]
        """#.utf8)
        let start = try #require(ISO8601DateFormatter().date(from: "2026-07-21T00:00:00Z"))
        let end = try #require(ISO8601DateFormatter().date(from: "2026-07-22T00:00:00Z"))

        let pushes = try GitHubActivityClient.decodePushActivities(
            from: data,
            startDate: start,
            endDate: end
        )
        let push = try #require(pushes.first)

        #expect(pushes.count == 1)
        #expect(push.repositoryName == "songvedem260597/RepoFocus")
        #expect(push.branchName == "feature/activity")
        #expect(push.commitCount == 3)
        #expect(push.distinctCommitCount == 2)
        #expect(push.commits.count == 2)
    }

    @Test("Commit messages are categorized into a change overview")
    func classifiesCommitMessages() {
        #expect(CommitChangeCategory.classify("feat: thêm màn hình hoạt động") == .feature)
        #expect(CommitChangeCategory.classify("fix(ui): sửa chữ bị rớt") == .fix)
        #expect(CommitChangeCategory.classify("docs: update README") == .documentation)
        #expect(CommitChangeCategory.classify("refactor activity store") == .refactor)
        #expect(CommitChangeCategory.classify("chore: bump version") == .maintenance)
    }

    @Test("Daily activity is cached in the local database")
    @MainActor
    func cachesDailyActivity() async throws {
        let date = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_721_520_000))
        let snapshot = DailyActivitySnapshot(
            date: date,
            pushes: [
                DailyPushActivity(
                    id: "push-1",
                    repositoryName: "owner/repo",
                    branchName: "main",
                    pushedAt: date.addingTimeInterval(3_600),
                    commitCount: 2,
                    distinctCommitCount: 2,
                    commits: []
                )
            ]
        )
        let persistence = MemoryPersistence()
        let tokenStore = MemoryTokenStore(token: "test-token")
        let store = RepositoryStore(
            persistence: persistence,
            tokenStore: tokenStore,
            githubClient: StaticGitHubClient(repositories: []),
            githubActivityClient: StaticGitHubActivityClient(snapshot: snapshot),
            useSampleDataWhenEmpty: false
        )

        await store.loadDailyActivity(for: date)

        let cachedSnapshot = try #require(store.activitySnapshot(for: date))
        #expect(Calendar.current.isDate(cachedSnapshot.date, inSameDayAs: snapshot.date))
        #expect(cachedSnapshot.pushes == snapshot.pushes)
        #expect(store.activityLoadState == .loaded)
        let persistedSnapshot = try #require(persistence.database?.activitySnapshots?.first)
        #expect(Calendar.current.isDate(persistedSnapshot.date, inSameDayAs: snapshot.date))
        #expect(persistedSnapshot.pushes == snapshot.pushes)
    }

    @Test("Today's reminders prioritize deadlines, blockers and branch conflicts")
    @MainActor
    func buildsTodayReminders() throws {
        let referenceDate = try #require(ISO8601DateFormatter().date(from: "2026-07-21T05:00:00Z"))
        let startOfDay = Calendar.current.startOfDay(for: referenceDate)

        func record(
            id: String,
            name: String,
            status: WorkStatus,
            deadline: Date?,
            focusOrder: Int,
            conflicts: Int = 0,
            isFocused: Bool = true
        ) -> RepositoryRecord {
            let github = GitHubRepository(
                id: id,
                name: name,
                nameWithOwner: "owner/\(name)",
                url: URL(string: "https://github.com/owner/\(name)")!,
                defaultBranch: "main"
            )
            let tracking = RepositoryTracking(
                repositoryID: id,
                status: status,
                priority: id == "overdue" ? .high : .medium,
                nextAction: "Tiếp tục xử lý",
                isFocused: isFocused,
                focusOrder: focusOrder,
                deadline: deadline,
                gitStatus: LocalGitStatus(
                    branch: "feature/reminder",
                    hasUpstream: true,
                    conflictCount: conflicts
                ),
                focusBranch: "feature/reminder"
            )
            return RepositoryRecord(github: github, tracking: tracking)
        }

        let records = [
            record(
                id: "normal",
                name: "Normal",
                status: .active,
                deadline: nil,
                focusOrder: 0
            ),
            record(
                id: "conflict",
                name: "Conflict",
                status: .active,
                deadline: nil,
                focusOrder: 1,
                conflicts: 2
            ),
            record(
                id: "blocked",
                name: "Blocked",
                status: .blocked,
                deadline: nil,
                focusOrder: 2
            ),
            record(
                id: "due-today",
                name: "DueToday",
                status: .active,
                deadline: startOfDay.addingTimeInterval(3_600),
                focusOrder: 3
            ),
            record(
                id: "overdue",
                name: "Overdue",
                status: .active,
                deadline: startOfDay.addingTimeInterval(-3_600),
                focusOrder: 4
            ),
            record(
                id: "done",
                name: "Done",
                status: .done,
                deadline: startOfDay,
                focusOrder: 5
            ),
            record(
                id: "paused",
                name: "Paused",
                status: .paused,
                deadline: startOfDay,
                focusOrder: 6
            ),
            record(
                id: "not-focused",
                name: "NotFocused",
                status: .active,
                deadline: startOfDay,
                focusOrder: 7,
                isFocused: false
            )
        ]
        let store = RepositoryStore(
            persistence: MemoryPersistence(database: RepositoryDatabase(repositories: records)),
            tokenStore: MemoryTokenStore(),
            githubClient: StaticGitHubClient(repositories: []),
            useSampleDataWhenEmpty: false
        )

        let reminders = store.todayReminderItems(on: referenceDate)

        #expect(reminders.map(\.repositoryID) == [
            "overdue", "due-today", "blocked", "conflict", "normal"
        ])
        #expect(reminders[0].reasons.contains(.overdue))
        #expect(reminders[1].reasons.contains(.dueToday))
        #expect(reminders[2].reasons.contains(.blocked))
        #expect(reminders[3].reasons.contains(.conflicts))
        #expect(reminders.allSatisfy { $0.branchName == "feature/reminder" })
    }

    @Test("GitHub remotes normalize for automatic local checkout detection")
    func normalizesGitHubRemotes() {
        #expect(LocalRepositoryLocator.normalizedGitHubSlug(
            "https://github.com/songvedem260597/RepoFocus.git"
        ) == "songvedem260597/RepoFocus")
        #expect(LocalRepositoryLocator.normalizedGitHubSlug(
            "git@github.com:songvedem260597/RepoFocus.git"
        ) == "songvedem260597/RepoFocus")
        #expect(LocalRepositoryLocator.normalizedGitHubSlug(
            "ssh://git@github.com/songvedem260597/RepoFocus.git"
        ) == "songvedem260597/RepoFocus")
    }

    @Test("GitLab remotes preserve nested namespaces for local detection")
    func normalizesGitLabRemotes() {
        #expect(LocalRepositoryLocator.normalizedGitLabSlug(
            "https://gitlab.com/company/mobile/RepoFocus.git"
        ) == "company/mobile/RepoFocus")
        #expect(LocalRepositoryLocator.normalizedGitLabSlug(
            "git@gitlab.com:company/mobile/RepoFocus.git"
        ) == "company/mobile/RepoFocus")
        #expect(LocalRepositoryLocator.normalizedGitLabSlug(
            "ssh://git@gitlab.com/company/mobile/RepoFocus.git"
        ) == "company/mobile/RepoFocus")
        #expect(LocalRepositoryLocator.normalizedGitHubSlug(
            "https://gitlab.com/company/mobile/RepoFocus.git"
        ) == nil)
    }

    @Test("GitLab API projects map to provider-aware repositories")
    func decodesGitLabProjects() throws {
        let data = Data(#"""
        [
          {
            "id": 42,
            "name": "RepoFocus",
            "path_with_namespace": "company/mobile/RepoFocus",
            "web_url": "https://gitlab.com/company/mobile/RepoFocus",
            "description": "GitLab project",
            "visibility": "private",
            "archived": false,
            "default_branch": "main",
            "open_issues_count": 3,
            "last_activity_at": "2026-07-21T09:30:00Z",
            "updated_at": "2026-07-21T09:00:00Z"
          }
        ]
        """#.utf8)

        let repository = try #require(GitLabCLIClient.decodeProjects(data).first)

        #expect(repository.id == "gitlab-42")
        #expect(repository.sourceProvider == .gitlab)
        #expect(repository.nameWithOwner == "company/mobile/RepoFocus")
        #expect(repository.isPrivate)
        #expect(repository.openIssueCount == 3)
        #expect(repository.defaultBranch == "main")
    }

    @Test("GitLab push events preserve provider, branch and commit totals")
    func decodesGitLabPushEvents() throws {
        let data = Data(#"""
        [
          {
            "id": 88,
            "project_id": 42,
            "action_name": "pushed to",
            "created_at": "2026-07-21T09:30:00.667Z",
            "push_data": {
              "commit_count": 2,
              "action": "pushed",
              "ref_type": "branch",
              "commit_from": "1111111111111111111111111111111111111111",
              "commit_to": "2222222222222222222222222222222222222222",
              "ref": "feature/gitlab",
              "commit_title": "feat: add GitLab activity"
            }
          }
        ]
        """#.utf8)
        let start = try #require(ISO8601DateFormatter().date(from: "2026-07-21T00:00:00Z"))
        let end = try #require(ISO8601DateFormatter().date(from: "2026-07-22T00:00:00Z"))

        let push = try #require(GitLabCLIClient.decodePushActivities(
            data,
            startDate: start,
            endDate: end,
            projectNames: [42: "company/mobile/RepoFocus"]
        ).first)

        #expect(push.sourceProvider == .gitlab)
        #expect(push.repositoryName == "company/mobile/RepoFocus")
        #expect(push.branchName == "feature/gitlab")
        #expect(push.commitCount == 2)
        #expect(push.commits.first?.subject == "feat: add GitLab activity")
    }

    @Test("Daily activity merges GitHub and GitLab pushes")
    @MainActor
    func mergesProviderActivity() async throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-07-21T00:00:00Z"))
        let githubPush = DailyPushActivity(
            id: "github-push",
            repositoryName: "owner/github-project",
            branchName: "main",
            pushedAt: date.addingTimeInterval(60),
            commitCount: 1,
            distinctCommitCount: 1,
            commits: [],
            provider: .github
        )
        let gitLabPush = DailyPushActivity(
            id: "gitlab-push",
            repositoryName: "team/gitlab-project",
            branchName: "develop",
            pushedAt: date.addingTimeInterval(120),
            commitCount: 2,
            distinctCommitCount: 2,
            commits: [],
            provider: .gitlab
        )
        let store = RepositoryStore(
            persistence: MemoryPersistence(),
            tokenStore: MemoryTokenStore(token: "github-token"),
            githubClient: StaticGitHubClient(repositories: []),
            gitLabClient: StaticGitLabClient(
                repositories: [],
                activitySnapshot: DailyActivitySnapshot(date: date, pushes: [gitLabPush])
            ),
            githubActivityClient: StaticGitHubActivityClient(
                snapshot: DailyActivitySnapshot(date: date, pushes: [githubPush])
            ),
            useSampleDataWhenEmpty: false
        )

        await store.loadDailyActivity(for: date)
        let snapshot = try #require(store.activitySnapshot(for: date))

        #expect(snapshot.totalPushes == 2)
        #expect(snapshot.totalCommits == 3)
        #expect(Set(snapshot.pushes.map(\.sourceProvider)) == [.github, .gitlab])
    }

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

    @Test("Git log output preserves commit subject and timestamp")
    func parsesRecentCommits() throws {
        let output = """
        abcdef1234567890\t1700000000\tHoàn thiện màn hình tập trung
        1234567890abcdef\t1699990000\tFix spacing in outline
        """

        let commits = LocalGitStatusChecker.parseLog(output)

        #expect(commits.count == 2)
        #expect(commits.first?.sha == "abcdef1234567890")
        #expect(commits.first?.subject == "Hoàn thiện màn hình tập trung")
        #expect(commits.first?.committedAt == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("Clone URLs produce safe destination folder names")
    func cloneFolderNames() throws {
        #expect(try LocalRepositoryCloner.folderName(
            from: "https://github.com/songvedem260597/RepoFocus.git"
        ) == "RepoFocus")
        #expect(try LocalRepositoryCloner.folderName(
            from: "git@github.com:songvedem260597/RepoFocus.git"
        ) == "RepoFocus")
        #expect(try LocalRepositoryCloner.folderName(
            from: "git@gitlab.com:company/mobile/RepoFocus.git"
        ) == "RepoFocus")
    }

    @Test("Codex deep link creates a new task in the selected workspace")
    func createsCodexWorkspaceLink() throws {
        let url = try #require(CodexWorkspaceLink.newTaskURL(
            workspacePath: "/Users/example/Projects/Repo Focus"
        ))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.scheme == "codex")
        #expect(components.host == "threads")
        #expect(components.path == "/new")
        #expect(components.queryItems?.first(where: { $0.name == "path" })?.value
            == "/Users/example/Projects/Repo Focus")
        #expect(CodexWorkspaceLink.newTaskURL(workspacePath: "relative/repo") == nil)
    }

    @Test("Local repository cloner executes a real git clone")
    func clonesLocalRepository() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("source.git", isDirectory: true)
        let destinationParent = root.appendingPathComponent("clones", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init", "--bare", source.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        let result = try LocalRepositoryCloner().clone(
            remoteURL: source.path,
            destinationParent: destinationParent.path
        )

        #expect(result.folderName == "source")
        #expect(FileManager.default.fileExists(
            atPath: URL(fileURLWithPath: result.path).appendingPathComponent(".git").path
        ))
    }

    @Test("Git clone output maps to monotonic overall progress")
    func parsesCloneProgress() throws {
        let receiving = try #require(LocalRepositoryCloner.progress(from: """
        Cloning into 'RepoFocus'...
        remote: Counting objects: 100% (50/50), done.
        Receiving objects: 50% (25/50)
        """))
        #expect(receiving.phase == .receivingObjects)
        #expect(receiving.phasePercentCompleted == 50)
        #expect(receiving.percentCompleted == 41)

        let resolving = try #require(LocalRepositoryCloner.progress(from: """
        Receiving objects: 100% (50/50), done.
        Resolving deltas: 50% (10/20)
        """))
        #expect(resolving.phase == .resolvingDeltas)
        #expect(resolving.phasePercentCompleted == 50)
        #expect(resolving.percentCompleted == 89)
        #expect(resolving.fractionCompleted > receiving.fractionCompleted)

        let checkout = try #require(LocalRepositoryCloner.progress(from: """
        Resolving deltas: 100% (20/20), done.
        Updating files: 50% (100/200)
        """))
        #expect(checkout.phase == .checkingOutFiles)
        #expect(checkout.phasePercentCompleted == 50)
        #expect(checkout.percentCompleted == 98)
        #expect(checkout.fractionCompleted > resolving.fractionCompleted)
    }

    @Test("A real clone streams progress before completion")
    func streamsRealCloneProgress() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let working = root.appendingPathComponent("working", isDirectory: true)
        let remote = root.appendingPathComponent("remote.git", isDirectory: true)
        let destinationParent = root.appendingPathComponent("clones", isDirectory: true)
        try FileManager.default.createDirectory(at: working, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGitForCloneTest(["init", working.path])
        try runGitForCloneTest(["-C", working.path, "config", "user.name", "RepoFocus Test"])
        try runGitForCloneTest(["-C", working.path, "config", "user.email", "test@repofocus.local"])
        for index in 0..<160 {
            let file = working.appendingPathComponent("fixture-\(index).txt")
            let content = Data(repeating: UInt8(index % 251), count: 2_048 + index)
            try content.write(to: file)
        }
        try runGitForCloneTest(["-C", working.path, "add", "-A"])
        try runGitForCloneTest(["-C", working.path, "commit", "-m", "Add progress fixtures"])
        try runGitForCloneTest(["clone", "--bare", working.path, remote.path])

        let recorder = CloneProgressRecorder()
        _ = try LocalRepositoryCloner().clone(
            remoteURL: remote.absoluteString,
            destinationParent: destinationParent.path,
            progressHandler: { progress in recorder.append(progress) }
        )

        let values = recorder.values
        #expect(values.contains { $0.phase == .receivingObjects })
        #expect(values.last == .completed)
        #expect(zip(values, values.dropFirst()).allSatisfy {
            $0.fractionCompleted <= $1.fractionCompleted
        })
    }

    @Test("Focus tracking is isolated for each branch")
    @MainActor
    func branchTrackingIsIndependent() throws {
        let original = try #require(SampleData.repositories.first)
        let store = RepositoryStore(
            persistence: MemoryPersistence(database: RepositoryDatabase(repositories: [original])),
            tokenStore: MemoryTokenStore(),
            githubClient: StaticGitHubClient(repositories: []),
            useSampleDataWhenEmpty: false
        )
        let originalBranch = try #require(store.repository(id: original.id)?.tracking.focusBranch)

        store.updateTracking(repositoryID: original.id) {
            $0.status = .active
            $0.progress = 70
            $0.nextAction = "Hoàn thiện branch chính"
        }
        store.setFocusBranch(repositoryID: original.id, branchName: "feature/clone-flow")

        #expect(store.repository(id: original.id)?.tracking.status == .inbox)
        #expect(store.repository(id: original.id)?.tracking.progress == 0)
        #expect(store.repository(id: original.id)?.tracking.nextAction.isEmpty == true)

        store.updateTracking(repositoryID: original.id) {
            $0.status = .planned
            $0.progress = 35
            $0.nextAction = "Thiết kế giao diện clone"
        }
        store.setFocusBranch(repositoryID: original.id, branchName: originalBranch)

        #expect(store.repository(id: original.id)?.tracking.status == .active)
        #expect(store.repository(id: original.id)?.tracking.progress == 70)
        #expect(store.repository(id: original.id)?.tracking.nextAction == "Hoàn thiện branch chính")

        store.setFocusBranch(repositoryID: original.id, branchName: "feature/clone-flow")
        #expect(store.repository(id: original.id)?.tracking.status == .planned)
        #expect(store.repository(id: original.id)?.tracking.progress == 35)
        #expect(store.repository(id: original.id)?.tracking.nextAction == "Thiết kế giao diện clone")
    }

    @Test("Cloning an account repository links its local checkout")
    @MainActor
    func cloneLinksRepository() async throws {
        var original = try #require(SampleData.repositories.first)
        original.tracking.localPath = nil
        let cloneResult = LocalRepositoryCloneResult(
            path: "/tmp/RepoFocus-clone",
            folderName: "RepoFocus-clone"
        )
        let store = RepositoryStore(
            persistence: MemoryPersistence(database: RepositoryDatabase(repositories: [original])),
            tokenStore: MemoryTokenStore(),
            githubClient: StaticGitHubClient(repositories: []),
            localGitChecker: StaticLocalGitChecker(
                status: LocalGitStatus(branch: "main", hasUpstream: true),
                commits: []
            ),
            localRepositoryCloner: StaticLocalRepositoryCloner(result: cloneResult),
            useSampleDataWhenEmpty: false
        )

        let repositoryID = await store.cloneRepository(
            repositoryID: original.id,
            remoteURL: original.github.url.absoluteString,
            destinationParent: "/tmp"
        )

        #expect(repositoryID == original.id)
        #expect(store.repository(id: original.id)?.tracking.localPath == cloneResult.path)
        #expect(store.repository(id: original.id)?.tracking.gitStatus?.branch == "main")
        #expect(store.cloneState == .succeeded(repositoryID: original.id, path: cloneResult.path))
    }

    @Test("A repository cloned from an external URL stays in the workspace")
    @MainActor
    func externalCloneCreatesRepository() async throws {
        let cloneResult = LocalRepositoryCloneResult(
            path: "/tmp/external-project",
            folderName: "external-project"
        )
        let store = RepositoryStore(
            persistence: MemoryPersistence(),
            tokenStore: MemoryTokenStore(),
            githubClient: StaticGitHubClient(repositories: []),
            localGitChecker: StaticLocalGitChecker(
                status: LocalGitStatus(branch: "develop", hasUpstream: true),
                commits: []
            ),
            localRepositoryCloner: StaticLocalRepositoryCloner(result: cloneResult),
            useSampleDataWhenEmpty: false
        )

        let repositoryID = try #require(await store.cloneRepository(
            repositoryID: nil,
            remoteURL: "https://gitlab.com/example/external-project.git",
            destinationParent: "/tmp"
        ))

        #expect(repositoryID.hasPrefix("external-"))
        #expect(store.repository(id: repositoryID)?.tracking.localPath == cloneResult.path)
        #expect(store.repository(id: repositoryID)?.github.sourceProvider == .gitlab)
        store.merge([])
        #expect(store.repository(id: repositoryID) != nil)
    }

    @Test("GitLab sync preserves GitHub repositories and adopts matching external checkout")
    @MainActor
    func gitLabSyncMergesProviders() async throws {
        let github = GitHubRepository(
            id: "github-1",
            name: "GitHubProject",
            nameWithOwner: "owner/GitHubProject",
            url: URL(string: "https://github.com/owner/GitHubProject")!,
            provider: .github
        )
        var externalTracking = RepositoryTracking(repositoryID: "external-gitlab")
        externalTracking.localPath = "/tmp/gitlab-project"
        externalTracking.nextAction = "Tiếp tục GitLab"
        let external = RepositoryRecord(
            github: GitHubRepository(
                id: "external-gitlab",
                name: "GitLabProject",
                nameWithOwner: "team/platform/GitLabProject",
                url: URL(string: "https://gitlab.com/team/platform/GitLabProject")!,
                provider: .gitlab
            ),
            tracking: externalTracking
        )
        let gitLab = GitHubRepository(
            id: "gitlab-77",
            name: "GitLabProject",
            nameWithOwner: "team/platform/GitLabProject",
            url: URL(string: "https://gitlab.com/team/platform/GitLabProject")!,
            provider: .gitlab
        )
        let store = RepositoryStore(
            persistence: MemoryPersistence(database: RepositoryDatabase(repositories: [
                RepositoryRecord(github: github), external
            ])),
            tokenStore: MemoryTokenStore(),
            githubClient: StaticGitHubClient(repositories: []),
            gitLabClient: StaticGitLabClient(repositories: [gitLab]),
            useSampleDataWhenEmpty: false
        )

        await store.syncGitLab()

        #expect(store.repository(id: github.id) != nil)
        #expect(store.repository(id: "external-gitlab") == nil)
        #expect(store.repository(id: gitLab.id)?.tracking.localPath == "/tmp/gitlab-project")
        #expect(store.repository(id: gitLab.id)?.tracking.nextAction == "Tiếp tục GitLab")
        #expect(store.repository(id: gitLab.id)?.tracking.repositoryID == gitLab.id)
        #expect(store.gitLabConnectionState == .connected)
    }

    @Test("A matching local commit automatically completes an outline task")
    @MainActor
    func commitCompletesOutlineTask() async throws {
        var record = try #require(SampleData.repositories.first)
        let taskCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        record.tracking.localPath = "/tmp/repofocus-test"
        record.tracking.usesOutlinePlan = true
        record.tracking.planItems = [
            RepositoryPlanItem(
                title: "Hoàn thiện màn hình tập trung",
                createdAt: taskCreatedAt
            )
        ]

        let checker = StaticLocalGitChecker(
            status: LocalGitStatus(branch: "main", hasUpstream: true),
            commits: [
                LocalGitCommit(
                    sha: "abcdef1234567890",
                    subject: "feat: hoan thien man hinh tap trung",
                    committedAt: taskCreatedAt.addingTimeInterval(60)
                )
            ]
        )
        let store = RepositoryStore(
            persistence: MemoryPersistence(database: RepositoryDatabase(repositories: [record])),
            tokenStore: MemoryTokenStore(),
            githubClient: StaticGitHubClient(repositories: []),
            localGitChecker: checker,
            useSampleDataWhenEmpty: false
        )

        await store.checkLocalGit(repositoryID: record.id)

        let result = try #require(store.repository(id: record.id))
        let item = try #require(result.tracking.planItems?.first)
        #expect(item.isCompleted)
        #expect(item.completionSource == .commit)
        #expect(item.matchedCommitSHA == "abcdef1234567890")
        #expect(result.displayProgress == 100)
        #expect(result.tracking.progress == 100)
    }

    @Test("Manual outline checks recalculate project progress")
    @MainActor
    func manualOutlineProgress() throws {
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

        store.setOutlinePlanEnabled(repositoryID: original.id, enabled: true)
        store.addPlanItem(repositoryID: original.id, title: "Việc thứ nhất")
        store.addPlanItem(repositoryID: original.id, title: "Việc thứ hai")
        let itemID = try #require(store.repository(id: original.id)?.tracking.planItems?.first?.id)
        store.togglePlanItem(repositoryID: original.id, itemID: itemID)

        let result = try #require(store.repository(id: original.id))
        #expect(result.displayProgress == 50)
        #expect(result.tracking.progress == 50)
        #expect(result.tracking.planItems?.first?.completionSource == .manual)

        store.setOutlinePlanEnabled(repositoryID: original.id, enabled: false)
        #expect(store.repository(id: original.id)?.tracking.progress == original.tracking.progress)
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
            lastSyncAt: Date(timeIntervalSince1970: 1_700_000_000),
            activitySnapshots: [
                DailyActivitySnapshot(
                    date: Date(timeIntervalSince1970: 1_700_000_000),
                    pushes: []
                )
            ]
        )

        try persistence.save(database)
        let loaded = try persistence.load()
        let decoded = try #require(loaded)

        #expect(decoded.repositories == database.repositories)
        #expect(decoded.lastSyncAt == database.lastSyncAt)
        #expect(decoded.activitySnapshots == database.activitySnapshots)

        try? FileManager.default.removeItem(at: directory)
    }
}

private func runGitForCloneTest(_ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(
            domain: "RepoFocusCloneProgressTests",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: "git command failed: \(arguments.joined(separator: " "))"]
        )
    }
}

private final class CloneProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [LocalRepositoryCloneProgress] = []

    func append(_ progress: LocalRepositoryCloneProgress) {
        lock.lock()
        storage.append(progress)
        lock.unlock()
    }

    var values: [LocalRepositoryCloneProgress] {
        lock.lock()
        defer { lock.unlock() }
        return storage
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

    init(token: String? = nil) {
        self.token = token
    }

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

private struct StaticGitHubActivityClient: GitHubActivityFetching {
    let snapshot: DailyActivitySnapshot

    func fetchDailyActivity(
        token: String,
        startDate: Date,
        endDate: Date
    ) async throws -> DailyActivitySnapshot {
        snapshot
    }
}

private struct StaticGitHubClient: GitHubRepositoryFetching {
    let repositories: [GitHubRepository]

    func fetchRepositories(token: String) async throws -> [GitHubRepository] {
        repositories
    }
}

private final class StaticGitLabClient: GitLabRepositoryFetching, @unchecked Sendable {
    let repositories: [GitHubRepository]
    let activitySnapshot: DailyActivitySnapshot?
    private var isEnabled = true

    init(repositories: [GitHubRepository], activitySnapshot: DailyActivitySnapshot? = nil) {
        self.repositories = repositories
        self.activitySnapshot = activitySnapshot
    }

    func status() -> GitLabCLIStatus {
        isEnabled ? .authenticated : .disabled
    }

    func setConnectionEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    func fetchRepositories() async throws -> [GitHubRepository] {
        repositories
    }

    func fetchDailyActivity(
        startDate: Date,
        endDate: Date,
        repositories: [GitHubRepository]
    ) async throws -> DailyActivitySnapshot {
        activitySnapshot ?? DailyActivitySnapshot(date: startDate, pushes: [])
    }
}

private struct StaticLocalGitChecker: LocalGitStatusChecking {
    let status: LocalGitStatus
    let commits: [LocalGitCommit]

    func check(path: String) throws -> LocalGitStatus {
        status
    }

    func recentCommits(path: String, limit: Int) throws -> [LocalGitCommit] {
        Array(commits.prefix(limit))
    }

    func branches(path: String) throws -> [String] {
        [status.branch ?? "main"]
    }
}

private struct StaticLocalRepositoryCloner: LocalRepositoryCloning {
    let result: LocalRepositoryCloneResult

    func clone(
        remoteURL: String,
        destinationParent: String,
        progressHandler: @escaping @Sendable (LocalRepositoryCloneProgress) -> Void
    ) throws -> LocalRepositoryCloneResult {
        progressHandler(.completed)
        return result
    }
}
