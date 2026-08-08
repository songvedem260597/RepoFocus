export type WorkStatus =
  | "inbox"
  | "planned"
  | "active"
  | "blocked"
  | "paused"
  | "done"
  | "archived";

export type Priority = "low" | "medium" | "high";

export interface GitStatus {
  branch: string | null;
  hasUpstream: boolean;
  aheadCount: number;
  behindCount: number;
  changedFileCount: number;
  conflictCount: number;
  checkedAt: string | null;
}

export type GitSequenceState = "none" | "merge" | "revert";
export type GitConflictChoice = "ours" | "theirs" | "markResolved";

export interface GitConflictState {
  files: string[];
  sequence: GitSequenceState;
}

export interface CommitInfo {
  sha: string;
  subject: string;
  author: string;
  committedAt: string;
}

export type PlanCompletionSource = "manual" | "commit";

export interface RepositoryPlanItem {
  id: string;
  title: string;
  commitKeyword: string;
  estimatedMinutes: number | null;
  isCompleted: boolean;
  completionSource: PlanCompletionSource | null;
  matchedCommitSha: string | null;
  createdAt: string | null;
  completedAt: string | null;
}

export interface RepositoryBranchTracking {
  branchName: string;
  status: WorkStatus;
  priority: Priority;
  progress: number;
  nextAction: string;
  notes: string;
  deadline: string | null;
  usesOutlinePlan: boolean;
  planItems: RepositoryPlanItem[];
  manualProgress: number | null;
  modifiedAt: string;
}

export interface Tracking {
  status: WorkStatus;
  priority: Priority;
  progress: number;
  nextAction: string;
  notes: string;
  isFocused: boolean;
  focusOrder: number;
  deadline: string | null;
  localPath: string | null;
  gitStatus: GitStatus | null;
  usesOutlinePlan: boolean;
  planItems: RepositoryPlanItem[];
  manualProgress: number | null;
  focusBranch: string | null;
  localBranches: string[] | null;
  branchTrackings: RepositoryBranchTracking[];
  modifiedAt: string;
}

export interface Repository {
  id: string;
  name: string;
  fullName: string;
  description: string | null;
  url: string | null;
  provider: string;
  isPrivate: boolean;
  isArchived: boolean;
  primaryLanguage: string | null;
  defaultBranch: string | null;
  openIssueCount: number;
  openPullRequestCount: number;
  pushedAt: string | null;
  updatedAt: string;
  tracking: Tracking;
}

export interface Settings {
  theme: "system" | "dark" | "light";
  language: "vi" | "en";
  scanDepth: number;
}

export interface AppData {
  version: number;
  repositories: Repository[];
  lastSyncAt: string | null;
  settings: Settings;
}

export interface ScanResult {
  repositories: Repository[];
  visitedFolders: number;
  skippedFolders: number;
}

export interface CloneProgress {
  phase: "preparing" | "receivingObjects" | "resolvingDeltas" | "checkingOutFiles" | "completed";
  percentCompleted: number;
  phasePercentCompleted: number;
}

export interface ContributionDay {
  date: string;
  count: number;
}

export interface GitActionResult {
  message: string;
  status: GitStatus;
}

export interface RemoteActivity {
  repositoryFullName: string;
  branch: string;
  sha: string;
  subject: string;
  author: string;
  committedAt: string;
}

export interface AutoFocusResult {
  data: AppData;
  focusedRepositoryIds: string[];
}

export type ViewKey = "focus" | "activity" | "all" | "attention" | "done" | "settings";
