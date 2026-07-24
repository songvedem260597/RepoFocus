import { invoke } from "@tauri-apps/api/core";
import type {
  AppData,
  CommitInfo,
  GitActionResult,
  GitConflictChoice,
  GitConflictState,
  GitStatus,
  RemoteActivity,
  Repository,
  ScanResult,
  Settings
} from "./types";

export const api = {
  load: () => invoke<AppData>("load_data"),
  saveRepository: (repository: Repository) =>
    invoke<AppData>("save_repository", { repository }),
  removeRepository: (repositoryId: string) =>
    invoke<AppData>("remove_repository", { repositoryId }),
  saveSettings: (settings: Settings) =>
    invoke<AppData>("save_settings", { settings }),
  importRepository: (path: string) =>
    invoke<AppData>("import_repository", { path }),
  scanRepositories: (root: string, maxDepth: number) =>
    invoke<ScanResult>("scan_repositories", { root, maxDepth }),
  autoDetectLocalRepository: (repositoryId: string) =>
    invoke<AppData>("auto_detect_local_repository", { repositoryId }),
  refreshGit: (path: string) => invoke<GitStatus>("refresh_git", { path }),
  listCommits: (path: string, limit = 100) =>
    invoke<CommitInfo[]>("list_commits", { path, limit }),
  listCommitsForBranch: (path: string, branch: string, limit = 100) =>
    invoke<CommitInfo[]>("list_commits_for_branch", { path, branch, limit }),
  listLocalBranches: (path: string) =>
    invoke<string[]>("list_local_branches", { path }),
  gitAction: (path: string, action: "fetch" | "pull" | "push") =>
    invoke<GitActionResult>("git_action", { path, action }),
  switchGitBranch: (path: string, branch: string) =>
    invoke<GitActionResult>("switch_git_branch", { path, branch }),
  commitAllGitChanges: (path: string, message: string) =>
    invoke<GitActionResult>("commit_all_git_changes", { path, message }),
  mergeGitBranch: (path: string, branch: string) =>
    invoke<GitActionResult>("merge_git_branch", { path, branch }),
  revertGitCommit: (path: string, sha: string) =>
    invoke<GitActionResult>("revert_git_commit", { path, sha }),
  gitConflictState: (path: string) =>
    invoke<GitConflictState>("git_conflict_state", { path }),
  resolveGitConflict: (path: string, file: string, choice: GitConflictChoice) =>
    invoke<GitActionResult>("resolve_git_conflict", { path, file, choice }),
  continueGitConflictOperation: (path: string) =>
    invoke<GitActionResult>("continue_git_conflict_operation", { path }),
  abortGitConflictOperation: (path: string) =>
    invoke<GitActionResult>("abort_git_conflict_operation", { path }),
  cloneRepository: (url: string, parent: string) =>
    invoke<AppData>("clone_repository", { url, parent }),
  syncGitHub: () => invoke<AppData>("sync_github"),
  githubActivity: (date: string) =>
    invoke<RemoteActivity[]>("github_activity", { date })
};
