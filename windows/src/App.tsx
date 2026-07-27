import {
  AlertTriangle,
  ArrowLeft,
  ArrowLeftRight,
  ArrowRight,
  ArrowUpCircle,
  BarChart3,
  Bell,
  Box,
  Brush,
  CalendarDays,
  Check,
  CheckCircle2,
  ChevronDown,
  CircleDot,
  Cloud,
  Download,
  ExternalLink,
  EyeOff,
  Folder,
  FolderGit2,
  Focus,
  GitBranch,
  GitCommitHorizontal,
  GitMerge,
  GitPullRequest,
  Github,
  History,
  LoaderCircle,
  Lock,
  Menu,
  Moon,
  Plus,
  RefreshCw,
  Search,
  Settings as SettingsIcon,
  ShieldCheck,
  Sun,
  Upload,
  Undo2,
  Zap,
  X
} from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { open } from "@tauri-apps/plugin-dialog";
import { openPath, openUrl } from "@tauri-apps/plugin-opener";
import { api } from "./api";
import type {
  AppData,
  CommitInfo,
  GitActionResult,
  GitConflictChoice,
  GitConflictState,
  GitStatus,
  Priority,
  RemoteActivity,
  Repository,
  RepositoryBranchTracking,
  RepositoryPlanItem,
  Settings,
  Tracking,
  ViewKey,
  WorkStatus
} from "./types";

const EMPTY_DATA: AppData = {
  version: 1,
  repositories: [],
  lastSyncAt: null,
  settings: { theme: "system", language: "vi", scanDepth: 4 }
};

const STATUS_LABELS: Record<WorkStatus, string> = {
  inbox: "Chưa phân loại",
  planned: "Đã lên kế hoạch",
  active: "Đang làm",
  blocked: "Bị chặn",
  paused: "Tạm dừng",
  done: "Hoàn thành",
  archived: "Đã lưu trữ"
};

const PRIORITY_LABELS: Record<Priority, string> = {
  low: "Thấp",
  medium: "Vừa",
  high: "Cao"
};

const VIEWS: Array<{
  id: ViewKey;
  label: string;
  icon: typeof Focus;
}> = [
  { id: "focus", label: "Đang tập trung", icon: Focus },
  { id: "activity", label: "Hoạt động", icon: BarChart3 },
  { id: "all", label: "Tất cả repo", icon: Box },
  { id: "attention", label: "Cần chú ý", icon: AlertTriangle },
  { id: "done", label: "Đã hoàn thành", icon: CheckCircle2 }
];

type WorkspaceDialog = "switch" | "commit" | "merge" | "history";

function asError(error: unknown): string {
  if (typeof error === "string") return error;
  if (error instanceof Error) return error.message;
  return "Đã xảy ra lỗi không xác định.";
}

function incompleteTaskCount(repository: Repository): number {
  if (repositoryIsCompleted(repository)) return 0;
  const planItems = repository.tracking.planItems ?? [];
  if (repository.tracking.usesOutlinePlan && planItems.length) {
    return planItems.filter((item) => !item.isCompleted).length;
  }
  return 1;
}

function isOverdue(repository: Repository): boolean {
  const deadline = repository.tracking.deadline;
  if (
    !deadline ||
    repository.isArchived ||
    repository.tracking.status === "done" ||
    repository.tracking.status === "archived" ||
    repositoryIsCompleted(repository) ||
    incompleteTaskCount(repository) === 0
  ) {
    return false;
  }
  // Store deadlines as local calendar dates. Comparing the ISO strings avoids
  // daylight-saving/time-zone shifts around midnight.
  return /^\d{4}-\d{2}-\d{2}$/.test(deadline) && deadline < localISODate();
}

function overdueTaskCount(repository: Repository): number {
  return isOverdue(repository) ? incompleteTaskCount(repository) : 0;
}

function overdueTaskLabel(repository: Repository): string {
  const openItems = repository.tracking.usesOutlinePlan
    ? (repository.tracking.planItems ?? []).filter((item) => !item.isCompleted)
    : [];
  return openItems[0]?.title || repository.tracking.nextAction || "Task quá hạn";
}

function needsAttention(repository: Repository): boolean {
  return isOverdue(repository);
}

function relativeDate(value: string | null): string {
  if (!value) return "chưa có hoạt động";
  const seconds = Math.max(0, Math.round((Date.now() - new Date(value).getTime()) / 1000));
  if (seconds < 60) return "vừa xong";
  if (seconds < 3600) return `${Math.floor(seconds / 60)} phút trước`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)} giờ trước`;
  if (seconds < 604800) return `${Math.floor(seconds / 86400)} ngày trước`;
  return new Intl.DateTimeFormat("vi-VN", { day: "2-digit", month: "2-digit", year: "numeric" }).format(
    new Date(value)
  );
}

function localISODate(value = new Date()): string {
  const year = value.getFullYear();
  const month = String(value.getMonth() + 1).padStart(2, "0");
  const day = String(value.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function autoFocusSuffix(count: number): string {
  return count > 0 ? ` Đã tự thêm ${count} repo có thay đổi hôm nay vào Focus.` : "";
}

function gitHealth(status: GitStatus | null): { label: string; tone: string } {
  if (!status) return { label: "Chưa kiểm tra Git", tone: "neutral" };
  if (status.conflictCount > 0) return { label: `${status.conflictCount} xung đột`, tone: "danger" };
  if (status.changedFileCount > 0) return { label: `Chưa commit ${status.changedFileCount}`, tone: "warning" };
  if (status.aheadCount > 0) return { label: `Chưa push ${status.aheadCount}`, tone: "info" };
  if (status.behindCount > 0) return { label: `Cần pull ${status.behindCount}`, tone: "warning" };
  if (!status.hasUpstream) return { label: "Chưa nối remote", tone: "neutral" };
  return { label: "Đã đồng bộ", tone: "success" };
}

function gitSignalCount(status: GitStatus | null): number {
  if (!status) return 0;
  let count = 0;
  if (status.conflictCount > 0) count += 1;
  if (status.changedFileCount > 0) count += 1;
  if (status.aheadCount > 0) count += 1;
  if (status.behindCount > 0) count += 1;
  if (count === 0) count = 1;
  return count;
}

function providerTitle(provider: string): string {
  const value = provider.trim().toLowerCase();
  if (value.includes("github")) return "GitHub";
  if (value.includes("gitlab")) return "GitLab";
  return provider || "Git";
}

function providerIcon(provider: string) {
  return provider.trim().toLowerCase().includes("github") ? Github : GitBranch;
}

function statusIcon(status: WorkStatus) {
  switch (status) {
    case "active": return Zap;
    case "planned": return CalendarDays;
    case "blocked": return AlertTriangle;
    case "paused": return CircleDot;
    case "done": return CheckCircle2;
    case "archived": return Box;
    default: return Box;
  }
}

function repositoryBranch(repository: Repository): string | null {
  return repository.tracking.focusBranch ?? repository.tracking.gitStatus?.branch ?? repository.defaultBranch;
}

function availableBranches(repository: Repository): string[] {
  return Array.from(new Set([
    ...(repository.tracking.localBranches ?? []),
    repository.tracking.focusBranch,
    repository.tracking.gitStatus?.branch,
    repository.defaultBranch
  ].filter((branch): branch is string => Boolean(branch?.trim())))).sort((left, right) =>
    left.localeCompare(right, "vi", { sensitivity: "base" })
  );
}

function switchBranchOptions(repository: Repository): string[] {
  const branches = availableBranches(repository);
  const currentBranch = repository.tracking.gitStatus?.branch ?? repositoryBranch(repository);
  return branches.filter((branch) => {
    if (branch === currentBranch) return false;
    if (!branch.startsWith("origin/")) return true;
    return !branches.includes(branch.slice("origin/".length));
  });
}

function mergeBranchOptions(repository: Repository): string[] {
  const currentBranch = repository.tracking.gitStatus?.branch ?? repositoryBranch(repository);
  return availableBranches(repository).filter(
    (branch) => branch !== currentBranch && branch !== `origin/${currentBranch ?? ""}`
  );
}

function planCompletionSummary(repository: Repository): { completed: number; total: number } {
  const items = repository.tracking.planItems ?? [];
  return { completed: items.filter((item) => item.isCompleted).length, total: items.length };
}

function copyPlanItems(items: RepositoryPlanItem[] | undefined | null): RepositoryPlanItem[] {
  return (items ?? []).map((item) => ({ ...item }));
}

function saveActiveBranchTracking(tracking: Tracking): Tracking {
  const branchName = tracking.focusBranch?.trim();
  if (!tracking.isFocused || !branchName) return tracking;

  const snapshot: RepositoryBranchTracking = {
    branchName,
    status: tracking.status,
    priority: tracking.priority,
    progress: tracking.progress,
    nextAction: tracking.nextAction,
    notes: tracking.notes,
    deadline: tracking.deadline,
    usesOutlinePlan: tracking.usesOutlinePlan,
    planItems: copyPlanItems(tracking.planItems),
    manualProgress: tracking.manualProgress ?? null,
    modifiedAt: tracking.modifiedAt
  };
  const branchTrackings = [...(tracking.branchTrackings ?? [])];
  const index = branchTrackings.findIndex((item) => item.branchName === branchName);
  if (index >= 0) branchTrackings[index] = snapshot;
  else branchTrackings.push(snapshot);
  return { ...tracking, focusBranch: branchName, branchTrackings };
}

function activateFocusBranch(
  tracking: Tracking,
  branchName: string,
  preserveCurrentValues: boolean
): Tracking {
  const normalized = branchName.trim();
  if (!normalized) return tracking;
  const snapshot = (tracking.branchTrackings ?? []).find((item) => item.branchName === normalized);
  let next: Tracking = { ...tracking, focusBranch: normalized };
  if (snapshot) {
    next = {
      ...next,
      status: snapshot.status,
      priority: snapshot.priority,
      progress: snapshot.progress,
      nextAction: snapshot.nextAction,
      notes: snapshot.notes,
      deadline: snapshot.deadline,
      usesOutlinePlan: snapshot.usesOutlinePlan,
      planItems: copyPlanItems(snapshot.planItems),
      manualProgress: snapshot.manualProgress ?? null
    };
  } else if (!preserveCurrentValues) {
    next = {
      ...next,
      status: "inbox",
      priority: "medium",
      progress: 0,
      nextAction: "",
      notes: "",
      deadline: null,
      usesOutlinePlan: false,
      planItems: [],
      manualProgress: null
    };
  }
  return saveActiveBranchTracking(next);
}

function stampTrackingChange(tracking: Tracking): Tracking {
  return saveActiveBranchTracking({ ...tracking, modifiedAt: new Date().toISOString() });
}

function normalizedCommitText(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase("vi")
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .join(" ");
}

function reconcileOutlineTracking(tracking: Tracking): Tracking {
  if (!tracking.usesOutlinePlan) return tracking;

  const planItems = tracking.planItems ?? [];
  const currentAction = normalizedCommitText(tracking.nextAction);
  const currentItem = planItems.find((item) => normalizedCommitText(item.title) === currentAction);
  const currentBelongsToPlan = !currentAction || Boolean(currentItem);
  const nextAction = currentItem && !currentItem.isCompleted
    ? tracking.nextAction
    : currentBelongsToPlan
      ? planItems.find((item) => !item.isCompleted)?.title ?? ""
      : tracking.nextAction;
  const progress = planItems.length
    ? Math.round((planItems.filter((item) => item.isCompleted).length / planItems.length) * 100)
    : 0;

  return { ...tracking, planItems, nextAction, progress };
}

function completePlanItemsFromCommits(tracking: Tracking, commits: CommitInfo[]): Tracking {
  const items = tracking.planItems ?? [];
  if (!tracking.usesOutlinePlan || !items.length || !commits.length) return tracking;

  let changed = false;
  const planItems = items.map((item) => {
    if (item.isCompleted || !item.createdAt) return item;
    const keyword = normalizedCommitText(item.commitKeyword);
    const createdAt = Date.parse(item.createdAt);
    if (!keyword || Number.isNaN(createdAt)) return item;
    const match = commits.find((commit) =>
      Date.parse(commit.committedAt) >= createdAt && normalizedCommitText(commit.subject).includes(keyword)
    );
    if (!match) return item;
    changed = true;
    return {
      ...item,
      isCompleted: true,
      completionSource: "commit" as const,
      matchedCommitSha: match.sha,
      completedAt: match.committedAt
    };
  });
  if (!changed) return tracking;

  return reconcileOutlineTracking({ ...tracking, planItems });
}

function repositoryIsCompleted(repository: Repository): boolean {
  return repository.tracking.status === "done" || displayedProgress(repository) >= 100;
}

function lastPushLabel(repository: Repository): string {
  return repository.pushedAt ? `Push ${relativeDate(repository.pushedAt)}` : "Chưa có lần push";
}

type FocusReminderKind = "overdue" | "today" | "blocked" | "conflict" | "next";

function isDueToday(repository: Repository): boolean {
  return (
    repository.tracking.status !== "done" &&
    repository.tracking.deadline === localISODate()
  );
}

function focusReminderKind(repository: Repository): FocusReminderKind {
  if (isOverdue(repository)) return "overdue";
  if (isDueToday(repository)) return "today";
  if (repository.tracking.status === "blocked") return "blocked";
  if ((repository.tracking.gitStatus?.conflictCount ?? 0) > 0) return "conflict";
  return "next";
}

function focusReminderLabel(repository: Repository): string {
  switch (focusReminderKind(repository)) {
    case "overdue": return `Quá hạn: ${overdueTaskLabel(repository)}`;
    case "today": return "Đến hạn hôm nay";
    case "blocked": return "Đang bị chặn";
    case "conflict": return `${repository.tracking.gitStatus?.conflictCount ?? 0} xung đột`;
    default: return repository.tracking.nextAction || "Chọn việc tiếp theo";
  }
}

function focusReminderIcon(repository: Repository) {
  switch (focusReminderKind(repository)) {
    case "overdue":
    case "today": return Bell;
    case "blocked": return AlertTriangle;
    case "conflict": return GitBranch;
    default: return Focus;
  }
}

function App() {
  const [data, setData] = useState<AppData>(EMPTY_DATA);
  const [activeView, setActiveView] = useState<ViewKey>("focus");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(true);
  const [working, setWorking] = useState<string | null>(null);
  const [toast, setToast] = useState<{ text: string; tone: "ok" | "error" } | null>(null);
  const [showClone, setShowClone] = useState(false);
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [cloneUrl, setCloneUrl] = useState("");
  const [cloneParent, setCloneParent] = useState("");
  const [cloneAutoDetected, setCloneAutoDetected] = useState(false);
  const [commits, setCommits] = useState<CommitInfo[]>([]);
  const [workspaceDialog, setWorkspaceDialog] = useState<WorkspaceDialog | null>(null);
  const [workspaceBranch, setWorkspaceBranch] = useState("");
  const [workspaceCommitMessage, setWorkspaceCommitMessage] = useState("");
  const [pendingRevertSha, setPendingRevertSha] = useState<string | null>(null);
  const [conflictState, setConflictState] = useState<GitConflictState | null>(null);
  const [showConflictResolver, setShowConflictResolver] = useState(false);
  const [confirmConflictAbort, setConfirmConflictAbort] = useState(false);
  const [newPlanItemTitle, setNewPlanItemTitle] = useState("");
  const [localDetection, setLocalDetection] = useState<"idle" | "searching" | "not-found">("idle");
  const [activityDate, setActivityDate] = useState(() => localISODate());
  const [activityCommits, setActivityCommits] = useState<
    Array<{ repository: Repository; commit: CommitInfo }>
  >([]);
  const searchRef = useRef<HTMLInputElement>(null);
  const saveTimer = useRef<number | null>(null);
  const lastAutoFocusCheckRef = useRef(0);
  const overdueNoticeShownRef = useRef<string | null>(null);

  const notify = useCallback((
    text: string,
    tone: "ok" | "error" = "ok",
    durationMs = 3800
  ) => {
    setToast({ text, tone });
    window.setTimeout(() => setToast(null), durationMs);
  }, []);

  const announceOverdueTasks = useCallback((repositories: Repository[]) => {
    const today = localISODate();
    if (overdueNoticeShownRef.current === today) return;
    const overdueRepositories = repositories.filter(needsAttention);
    const taskCount = overdueRepositories.reduce(
      (total, repository) => total + overdueTaskCount(repository),
      0
    );
    if (!taskCount) return;

    overdueNoticeShownRef.current = today;
    const preview = overdueRepositories
      .slice(0, 2)
      .map((repository) => `${repository.name}: ${overdueTaskLabel(repository)}`)
      .join(" · ");
    const remaining = overdueRepositories.length - Math.min(overdueRepositories.length, 2);
    notify(
      `Bạn có ${taskCount} task quá hạn chưa hoàn thành`
        + (preview ? ` — ${preview}${remaining > 0 ? ` · và ${remaining} repo khác` : ""}` : "")
        + ". Mở “Cần chú ý” để xử lý.",
      "error",
      8_000
    );
  }, [notify]);

  const runAutoFocusToday = useCallback(async (announce = true) => {
    const result = await api.autoFocusToday(localISODate());
    setData(result.data);
    setSelectedId((current) => current ?? result.data.repositories[0]?.id ?? null);
    if (announce && result.focusedRepositoryIds.length) {
      const focusedCount = result.focusedRepositoryIds.length;
      const focusedNames = result.focusedRepositoryIds
        .map((repositoryId) =>
          result.data.repositories.find((repository) => repository.id === repositoryId)?.name
        )
        .filter((name): name is string => Boolean(name));
      const preview = focusedNames.slice(0, 2).join(", ");
      const remaining = focusedCount - Math.min(focusedNames.length, 2);
      notify(
        `Đã tự thêm ${focusedCount} repo có thay đổi hôm nay vào Focus`
          + (preview ? `: ${preview}${remaining > 0 ? ` và ${remaining} repo khác` : ""}.` : ".")
      );
    }
    return result;
  }, [notify]);

  const load = useCallback(async () => {
    try {
      const next = await api.load();
      setData(next);
      setSelectedId((current) => current ?? next.repositories[0]?.id ?? null);
    } catch (error) {
      notify(asError(error), "error");
    } finally {
      setLoading(false);
    }
  }, [notify]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    if (loading) return;
    const checkTodayActivity = () => {
      const now = Date.now();
      if (now - lastAutoFocusCheckRef.current < 60_000) return;
      lastAutoFocusCheckRef.current = now;
      void runAutoFocusToday(false)
        .then((result) => announceOverdueTasks(result.data.repositories))
        .catch((error) => notify(asError(error), "error"));
    };
    checkTodayActivity();
    window.addEventListener("focus", checkTodayActivity);
    return () => window.removeEventListener("focus", checkTodayActivity);
  }, [announceOverdueTasks, loading, notify, runAutoFocusToday]);

  useEffect(() => {
    if (!loading) announceOverdueTasks(data.repositories);
  }, [announceOverdueTasks, data.repositories, loading]);

  useEffect(() => {
    const resolvedTheme =
      data.settings.theme === "system"
        ? window.matchMedia("(prefers-color-scheme: light)").matches
          ? "light"
          : "dark"
        : data.settings.theme;
    document.documentElement.dataset.theme = resolvedTheme;
  }, [data.settings.theme]);

  useEffect(() => {
    const shortcut = (event: KeyboardEvent) => {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        searchRef.current?.focus();
      }
    };
    window.addEventListener("keydown", shortcut);
    return () => window.removeEventListener("keydown", shortcut);
  }, []);

  const counts = useMemo(
    () => ({
      focus: data.repositories.filter(
        (repo) => repo.tracking.isFocused && repo.tracking.status !== "archived"
      ).length,
      activity: activityCommits.length,
      all: data.repositories.length,
      attention: data.repositories.reduce(
        (total, repository) => total + overdueTaskCount(repository),
        0
      ),
      done: data.repositories.filter(
        (repo) => repo.tracking.status === "done" || repo.tracking.status === "archived"
      ).length,
      settings: 0
    }),
    [activityCommits.length, data.repositories]
  );

  const repositories = useMemo(() => {
    const normalizedQuery = query.trim().toLocaleLowerCase("vi");
    return data.repositories
      .filter((repository) => {
        if (activeView === "focus") {
          return repository.tracking.isFocused && repository.tracking.status !== "archived";
        }
        if (activeView === "activity" || activeView === "settings") return false;
        if (activeView === "attention") return needsAttention(repository);
        if (activeView === "done") {
          return repository.tracking.status === "done" || repository.tracking.status === "archived";
        }
        return true;
      })
      .filter((repository) => {
        if (!normalizedQuery) return true;
        return [
          repository.name,
          repository.fullName,
          repository.description,
          repository.tracking.nextAction,
          ...(repository.tracking.planItems ?? []).map((item) => item.title)
        ]
          .filter(Boolean)
          .some((value) => value!.toLocaleLowerCase("vi").includes(normalizedQuery));
      })
      .sort((left, right) => {
        if (activeView === "focus" && left.tracking.focusOrder !== right.tracking.focusOrder) {
          return left.tracking.focusOrder - right.tracking.focusOrder;
        }
        if (activeView === "all") {
          return new Date(right.pushedAt ?? right.updatedAt).getTime() -
            new Date(left.pushedAt ?? left.updatedAt).getTime();
        }
        if (activeView === "attention") {
          const leftDeadline = left.tracking.deadline ?? "9999-12-31";
          const rightDeadline = right.tracking.deadline ?? "9999-12-31";
          if (leftDeadline !== rightDeadline) {
            return leftDeadline.localeCompare(rightDeadline);
          }
          const priority = { high: 0, medium: 1, low: 2 };
          const priorityDiff = priority[left.tracking.priority] - priority[right.tracking.priority];
          if (priorityDiff !== 0) return priorityDiff;
          return left.name.localeCompare(right.name, "vi", { sensitivity: "base" });
        }
        if (activeView === "done") {
          return new Date(right.tracking.modifiedAt).getTime() - new Date(left.tracking.modifiedAt).getTime();
        }
        if (left.tracking.isFocused !== right.tracking.isFocused) {
          return left.tracking.isFocused ? -1 : 1;
        }
        const priority = { high: 0, medium: 1, low: 2 };
        const priorityDiff = priority[left.tracking.priority] - priority[right.tracking.priority];
        if (priorityDiff !== 0) return priorityDiff;
        return left.name.localeCompare(right.name, "vi", { sensitivity: "base" });
      });
  }, [activeView, data.repositories, query]);

  const loadActivity = useCallback(async () => {
    const localRepositories = data.repositories.filter((repo) => repo.tracking.localPath);
    setWorking("activity");
    try {
      const results = await Promise.all(
        localRepositories.map(async (repository) => ({
          repository,
          commits: await api.listCommits(repository.tracking.localPath!, 200)
        }))
      );
      const localActivity = results
        .flatMap(({ repository, commits }) =>
          commits.map((commit) => ({ repository, commit }))
        )
        .filter(({ commit }) => {
          const local = new Date(commit.committedAt);
          const year = local.getFullYear();
          const month = String(local.getMonth() + 1).padStart(2, "0");
          const day = String(local.getDate()).padStart(2, "0");
          return `${year}-${month}-${day}` === activityDate;
        })
        .sort(
          (left, right) =>
            new Date(right.commit.committedAt).getTime() -
            new Date(left.commit.committedAt).getTime()
        );
      const remote = await api.githubActivity(activityDate).catch((error) => {
        notify(asError(error), "error");
        return [] as RemoteActivity[];
      });
      const remoteActivity = remote.flatMap((record) => {
        const repository = data.repositories.find(
          (item) => item.fullName.toLowerCase() === record.repositoryFullName.toLowerCase()
        );
        if (!repository) return [];
        return [{
          repository,
          commit: {
            sha: record.sha,
            subject: record.subject,
            author: record.author,
            committedAt: record.committedAt
          }
        }];
      });
      setActivityCommits(
        [...localActivity, ...remoteActivity].sort(
          (left, right) =>
            new Date(right.commit.committedAt).getTime() -
            new Date(left.commit.committedAt).getTime()
        )
      );
    } catch (error) {
      notify(asError(error), "error");
    } finally {
      setWorking(null);
    }
  }, [activityDate, data.repositories, notify]);

  useEffect(() => {
    if (activeView === "activity") void loadActivity();
  }, [activeView, activityDate, loadActivity]);

  const refreshActivity = useCallback(async () => {
    await loadActivity();
    if (activityDate === localISODate()) {
      await runAutoFocusToday();
    }
  }, [activityDate, loadActivity, runAutoFocusToday]);

  useEffect(() => {
    if (!repositories.length) {
      setSelectedId(null);
      return;
    }
    if (!repositories.some((repository) => repository.id === selectedId)) {
      setSelectedId(repositories[0].id);
    }
  }, [repositories, selectedId]);

  useEffect(() => {
    setConflictState(null);
    setShowConflictResolver(false);
    setConfirmConflictAbort(false);
    setLocalDetection("idle");
  }, [selectedId]);

  const selected = data.repositories.find((repository) => repository.id === selectedId) ?? null;
  const selectedProgress = selected ? displayedProgress(selected) : 0;
  const workspaceBusy = Boolean(
    working === "git" || working === "pull" || working === "push" || working?.startsWith("workspace-")
  );
  const workspaceHasConflict = Boolean(
    conflictState && (conflictState.files.length > 0 || conflictState.sequence !== "none")
  );

  const updateRepository = useCallback(
    (
      repositoryId: string,
      update: (repository: Repository) => Repository,
      saveImmediately = false
    ) => {
      let changed: Repository | null = null;
      setData((current) => ({
        ...current,
        repositories: current.repositories.map((repository) => {
          if (repository.id !== repositoryId) return repository;
          const next = update(repository);
          changed = { ...next, tracking: stampTrackingChange(next.tracking) };
          return changed;
        })
      }));
      if (saveTimer.current) window.clearTimeout(saveTimer.current);
      saveTimer.current = window.setTimeout(
        async () => {
          if (!changed) return;
          try {
            const next = await api.saveRepository(changed);
            setData(next);
          } catch (error) {
            notify(asError(error), "error");
          }
        },
        saveImmediately ? 0 : 450
      );
    },
    [notify]
  );

  const updateSelected = useCallback(
    (update: (repository: Repository) => Repository, saveImmediately = false) => {
      if (!selectedId) return;
      updateRepository(selectedId, update, saveImmediately);
    },
    [selectedId, updateRepository]
  );

  const refreshConflictState = async (path: string): Promise<GitConflictState> => {
    const next = await api.gitConflictState(path);
    setConflictState(next.files.length || next.sequence !== "none" ? next : null);
    return next;
  };

  const setFocusBranch = async (focusBranch: string) => {
    updateSelected(
      (repository) => {
        const saved = saveActiveBranchTracking(repository.tracking);
        return {
          ...repository,
          tracking: activateFocusBranch(saved, focusBranch, false)
        };
      },
      true
    );
    if (!selected?.tracking.localPath) return;
    try {
      const commits = await api.listCommitsForBranch(selected.tracking.localPath, focusBranch);
      updateSelected(
        (repository) => ({
          ...repository,
          tracking: completePlanItemsFromCommits(repository.tracking, commits)
        }),
        true
      );
    } catch {
      // The branch may only exist remotely; branch selection itself stays usable.
    }
  };

  const setOutlinePlan = (usesOutlinePlan: boolean) => {
    updateSelected(
      (repository) => {
        const tracking = repository.tracking;
        const nextTracking = {
          ...tracking,
          usesOutlinePlan,
          manualProgress: usesOutlinePlan && !tracking.usesOutlinePlan
            ? tracking.progress
            : !usesOutlinePlan && tracking.usesOutlinePlan
              ? null
              : tracking.manualProgress,
          progress: !usesOutlinePlan && tracking.usesOutlinePlan
            ? tracking.manualProgress ?? tracking.progress
            : tracking.progress
        };
        return {
          ...repository,
          tracking: usesOutlinePlan ? reconcileOutlineTracking(nextTracking) : nextTracking
        };
      },
      true
    );
  };

  const addPlanItem = () => {
    const title = newPlanItemTitle.trim();
    if (!title) return;
    const item: RepositoryPlanItem = {
      id: crypto.randomUUID(),
      title,
      commitKeyword: title,
      estimatedMinutes: null,
      isCompleted: false,
      completionSource: null,
      matchedCommitSha: null,
      createdAt: new Date().toISOString(),
      completedAt: null
    };
    updateSelected(
      (repository) => {
        const tracking = repository.tracking;
        const nextTracking = {
          ...tracking,
          usesOutlinePlan: true,
          manualProgress: tracking.usesOutlinePlan
            ? tracking.manualProgress
            : tracking.progress,
          nextAction: tracking.nextAction.trim() ? tracking.nextAction : title,
          planItems: [...(tracking.planItems ?? []), item]
        };
        return {
          ...repository,
          tracking: reconcileOutlineTracking(nextTracking)
        };
      },
      true
    );
    setNewPlanItemTitle("");
  };

  const updatePlanItem = (itemId: string, update: (item: RepositoryPlanItem) => RepositoryPlanItem) => {
    updateSelected(
      (repository) => ({
        ...repository,
        tracking: reconcileOutlineTracking({
          ...repository.tracking,
          planItems: (repository.tracking.planItems ?? []).map((item) => item.id === itemId ? update(item) : item)
        })
      })
    );
  };

  const removePlanItem = (itemId: string) => {
    updateSelected(
      (repository) => {
        const removedItem = (repository.tracking.planItems ?? []).find((item) => item.id === itemId);
        const nextAction = removedItem &&
          normalizedCommitText(repository.tracking.nextAction) === normalizedCommitText(removedItem.title)
          ? ""
          : repository.tracking.nextAction;
        return {
          ...repository,
          tracking: reconcileOutlineTracking({
            ...repository.tracking,
            nextAction,
            planItems: (repository.tracking.planItems ?? []).filter((item) => item.id !== itemId)
          })
        };
      },
      true
    );
  };

  const toggleRepositoryFocus = useCallback(
    async (repository: Repository) => {
      let changed: Repository | null = null;
      setData((current) => ({
        ...current,
        repositories: current.repositories.map((item) => {
          if (item.id !== repository.id) return item;
          const isFocused = !item.tracking.isFocused;
          const nextFocusOrder = isFocused
            ? Math.max(
                -1,
                ...current.repositories
                  .filter((candidate) => candidate.tracking.isFocused)
                  .map((candidate) => candidate.tracking.focusOrder)
              ) + 1
            : item.tracking.focusOrder;
          const suggestedBranch = item.tracking.focusBranch
            ?? item.tracking.gitStatus?.branch
            ?? item.defaultBranch
            ?? "main";
          const baseTracking = {
            ...item.tracking,
            focusOrder: nextFocusOrder,
            modifiedAt: new Date().toISOString()
          };
          const tracking = isFocused
            ? activateFocusBranch({ ...baseTracking, isFocused: true }, suggestedBranch, true)
            : { ...saveActiveBranchTracking(baseTracking), isFocused: false };
          const next = {
            ...item,
            tracking
          };
          changed = next;
          return next;
        })
      }));
      if (!changed) return;
      try {
        setData(await api.saveRepository(changed));
      } catch (error) {
        notify(asError(error), "error");
        await load();
      }
    },
    [load, notify]
  );

  const chooseAndImport = async () => {
    const path = await open({ directory: true, multiple: false, title: "Chọn Git repository" });
    if (!path) return;
    setWorking("import");
    try {
      const next = await api.importRepository(path);
      setData(next);
      const autoFocus = await runAutoFocusToday(false);
      const imported = autoFocus.data.repositories.find((repo) => repo.tracking.localPath === path);
      if (imported) setSelectedId(imported.id);
      notify(`Đã thêm repository từ máy.${autoFocusSuffix(autoFocus.focusedRepositoryIds.length)}`);
    } catch (error) {
      notify(asError(error), "error");
    } finally {
      setWorking(null);
    }
  };

  const autoDetectLocalRepository = async () => {
    if (!selected || selected.tracking.localPath) return;
    setLocalDetection("searching");
    setWorking("local-search");
    try {
      const next = await api.autoDetectLocalRepository(selected.id);
      const matched = next.repositories.find((repository) => repository.id === selected.id);
      if (!matched?.tracking.localPath) {
        setData(next);
        setLocalDetection("not-found");
        return;
      }

      const planBranch = matched.tracking.focusBranch
        ?? matched.tracking.gitStatus?.branch
        ?? matched.defaultBranch;
      if (planBranch) {
        const commits = await api.listCommitsForBranch(matched.tracking.localPath, planBranch).catch(() => [] as CommitInfo[]);
        const completed = {
          ...matched,
          tracking: completePlanItemsFromCommits(matched.tracking, commits)
        };
        setData(await api.saveRepository(completed));
      } else {
        setData(next);
      }
      const autoFocus = await runAutoFocusToday(false);
      setLocalDetection("idle");
      notify(`Đã tìm thấy checkout Git trên máy.${autoFocusSuffix(autoFocus.focusedRepositoryIds.length)}`);
    } catch (error) {
      setLocalDetection("idle");
      notify(asError(error), "error");
    } finally {
      setWorking(null);
    }
  };

  const chooseAndScan = async () => {
    const root = await open({ directory: true, multiple: false, title: "Chọn thư mục chứa source code" });
    if (!root) return;
    setWorking("scan");
    try {
      const result = await api.scanRepositories(root, data.settings.scanDepth);
      const autoFocus = await runAutoFocusToday(false);
      notify(
        `Đã tìm thấy ${result.repositories.length} Git repository.`
          + autoFocusSuffix(autoFocus.focusedRepositoryIds.length)
      );
    } catch (error) {
      notify(asError(error), "error");
    } finally {
      setWorking(null);
    }
  };

  const syncGitHub = async () => {
    setWorking("sync");
    try {
      const next = await api.syncGitHub();
      setData(next);
      const autoFocus = await runAutoFocusToday(false);
      if (!selectedId && autoFocus.data.repositories[0]) {
        setSelectedId(autoFocus.data.repositories[0].id);
      }
      notify(
        `Đã đồng bộ ${next.repositories.filter((repo) => repo.provider === "github").length} repo GitHub.`
          + autoFocusSuffix(autoFocus.focusedRepositoryIds.length)
      );
    } catch (error) {
      notify(asError(error), "error");
    } finally {
      setWorking(null);
    }
  };

  const refreshGit = async () => {
    if (!selected?.tracking.localPath) return;
    setWorking("git");
    try {
      const [status, localBranches] = await Promise.all([
        api.refreshGit(selected.tracking.localPath),
        api.listLocalBranches(selected.tracking.localPath).catch(() => selected.tracking.localBranches ?? [])
      ]);
      const planBranch = selected.tracking.focusBranch ?? status.branch ?? selected.defaultBranch;
      const planCommits = planBranch
        ? await api.listCommitsForBranch(selected.tracking.localPath, planBranch).catch(() => [] as CommitInfo[])
        : [];
      await refreshConflictState(selected.tracking.localPath).catch(() => setConflictState(null));
      updateSelected(
        (repository) => {
          const tracking = {
            ...repository.tracking,
            gitStatus: status,
            localBranches
          };
          const shouldActivateBranch = tracking.isFocused && !tracking.focusBranch;
          const activeTracking = shouldActivateBranch
            ? activateFocusBranch(tracking, status.branch ?? repository.defaultBranch ?? "main", true)
            : tracking;
          return {
            ...repository,
            tracking: completePlanItemsFromCommits(activeTracking, planCommits)
          };
        },
        true
      );
      notify("Đã cập nhật trạng thái Git.");
    } catch (error) {
      notify(asError(error), "error");
    } finally {
      setWorking(null);
    }
  };

  const applyGitWorkspaceResult = async (
    result: GitActionResult,
    options: { followCurrentBranch?: boolean } = {}
  ) => {
    const localPath = selected?.tracking.localPath;
    const localBranches = localPath
      ? await api.listLocalBranches(localPath).catch(() => selected?.tracking.localBranches ?? [])
      : selected?.tracking.localBranches ?? [];
    const planBranch = options.followCurrentBranch
      ? result.status.branch
      : selected?.tracking.focusBranch ?? result.status.branch ?? selected?.defaultBranch;
    const planCommits = localPath && planBranch
      ? await api.listCommitsForBranch(localPath, planBranch).catch(() => [] as CommitInfo[])
      : [];
    updateSelected(
      (repository) => {
        const tracking = {
          ...repository.tracking,
          gitStatus: result.status,
          localBranches
        };
        const desiredBranch = options.followCurrentBranch
          ? result.status.branch
          : tracking.isFocused && !tracking.focusBranch
            ? result.status.branch ?? repository.defaultBranch
            : null;
        const activeTracking = desiredBranch
          ? activateFocusBranch(saveActiveBranchTracking(tracking), desiredBranch, !options.followCurrentBranch)
          : tracking;
        return {
          ...repository,
          tracking: completePlanItemsFromCommits(activeTracking, planCommits)
        };
      },
      true
    );
  };

  const refreshWorkspaceAfterFailure = async (path: string): Promise<GitConflictState | null> => {
    try {
      const [status, localBranches] = await Promise.all([
        api.refreshGit(path),
        api.listLocalBranches(path).catch(() => selected?.tracking.localBranches ?? [])
      ]);
      updateSelected(
        (repository) => {
          const tracking = { ...repository.tracking, gitStatus: status, localBranches };
          return {
            ...repository,
            tracking: tracking.isFocused && !tracking.focusBranch && status.branch
              ? activateFocusBranch(tracking, status.branch, true)
              : tracking
          };
        },
        true
      );
      return await refreshConflictState(path).catch(() => {
        setConflictState(null);
        return null;
      });
    } catch {
      // Preserve the original Git error when the post-failure status refresh also fails.
      return null;
    }
  };

  const executeGitAction = async (action: "pull" | "push") => {
    if (!selected?.tracking.localPath) return;
    const path = selected.tracking.localPath;
    setWorking(action);
    try {
      const result = await api.gitAction(path, action);
      await applyGitWorkspaceResult(result);
      await refreshConflictState(path).catch(() => setConflictState(null));
      notify(result.message);
    } catch (error) {
      const conflict = await refreshWorkspaceAfterFailure(path);
      if (conflict && (conflict.files.length || conflict.sequence !== "none")) {
        setConfirmConflictAbort(false);
        setShowConflictResolver(true);
      }
      notify(asError(error), "error");
    } finally {
      setWorking(null);
    }
  };

  const openWorkspaceDialog = (dialog: WorkspaceDialog) => {
    if (!selected?.tracking.localPath) return;
    const options = dialog === "switch"
      ? switchBranchOptions(selected)
      : dialog === "merge"
        ? mergeBranchOptions(selected)
        : [];
    setPendingRevertSha(null);
    if (dialog === "switch" || dialog === "merge") {
      setWorkspaceBranch(options[0] ?? "");
    }
    if (dialog === "commit") setWorkspaceCommitMessage("");
    setWorkspaceDialog(dialog);

    if (dialog === "history") {
      const path = selected.tracking.localPath;
      setWorking("workspace-history");
      void api.listCommits(path)
        .then(setCommits)
        .catch((error) => notify(asError(error), "error"))
        .finally(() => setWorking(null));
    }
  };

  const executeWorkspaceAction = async (
    action: "switch" | "commit" | "merge" | "revert",
    value: string
  ) => {
    if (!selected?.tracking.localPath) return;
    const path = selected.tracking.localPath;
    setWorking(`workspace-${action}`);
    try {
      const result = action === "switch"
        ? await api.switchGitBranch(path, value)
        : action === "commit"
          ? await api.commitAllGitChanges(path, value)
          : action === "merge"
            ? await api.mergeGitBranch(path, value)
            : await api.revertGitCommit(path, value);
      await applyGitWorkspaceResult(result, { followCurrentBranch: action === "switch" });
      await refreshConflictState(path).catch(() => setConflictState(null));
      if (action === "commit" || action === "revert") {
        setCommits(await api.listCommits(path));
      }
      if (action === "revert") {
        setPendingRevertSha(null);
      } else {
        setWorkspaceDialog(null);
      }
      notify(result.message);
    } catch (error) {
      const conflict = await refreshWorkspaceAfterFailure(path);
      if (conflict && (conflict.files.length || conflict.sequence !== "none")) {
        setWorkspaceDialog(null);
        setConfirmConflictAbort(false);
        setShowConflictResolver(true);
      }
      notify(asError(error), "error");
    } finally {
      setWorking(null);
    }
  };

  const executeConflictAction = async (
    action: "resolve" | "continue" | "abort",
    file?: string,
    choice?: GitConflictChoice
  ) => {
    if (!selected?.tracking.localPath) return;
    if (action === "resolve" && (!file || !choice)) return;
    const path = selected.tracking.localPath;
    setWorking(`workspace-${action}-conflict`);
    try {
      const result = action === "resolve"
        ? await api.resolveGitConflict(path, file!, choice!)
        : action === "continue"
          ? await api.continueGitConflictOperation(path)
          : await api.abortGitConflictOperation(path);
      await applyGitWorkspaceResult(result);
      const next = await refreshConflictState(path).catch(() => null);
      if (!next || (!next.files.length && next.sequence === "none")) {
        setShowConflictResolver(false);
        setConfirmConflictAbort(false);
      }
      notify(result.message);
    } catch (error) {
      await refreshWorkspaceAfterFailure(path);
      notify(asError(error), "error");
    } finally {
      setWorking(null);
    }
  };

  const openCodexTask = async () => {
    if (!selected?.tracking.localPath) return;
    const target = `codex://threads/new?${new URLSearchParams({ path: selected.tracking.localPath }).toString()}`;
    try {
      await openUrl(target);
    } catch (error) {
      notify(`Không thể mở tác vụ mới trong Codex: ${asError(error)}`, "error");
    }
  };

  const openConflictFile = async (file: string) => {
    const repositoryPath = selected?.tracking.localPath;
    const relativePath = file.replaceAll("/", "\\");
    const segments = relativePath.split("\\");
    if (!repositoryPath || !relativePath || segments.some((segment) => !segment || segment === "." || segment === "..")) {
      notify("Đường dẫn file conflict không hợp lệ.", "error");
      return;
    }
    try {
      await openPath(`${repositoryPath}\\${relativePath}`);
    } catch (error) {
      notify(`Không thể mở file conflict: ${asError(error)}`, "error");
    }
  };

  const chooseCloneParent = async () => {
    const path = await open({ directory: true, multiple: false, title: "Chọn thư mục lưu repository" });
    if (path) setCloneParent(path);
  };

  const openCloneDialog = () => {
    const detectedUrl = selected && !selected.tracking.localPath ? selected.url : null;
    if (detectedUrl) {
      setCloneUrl(detectedUrl);
      setCloneAutoDetected(true);
    } else {
      setCloneUrl("");
      setCloneAutoDetected(false);
    }
    setShowClone(true);
  };

  const clone = async () => {
    if (!cloneUrl.trim() || !cloneParent) {
      notify("Hãy nhập URL và chọn thư mục lưu.", "error");
      return;
    }
    setWorking("clone");
    try {
      const next = await api.cloneRepository(cloneUrl, cloneParent);
      setData(next);
      const autoFocus = await runAutoFocusToday(false);
      const imported = autoFocus.data.repositories.find(
        (repo) => repo.tracking.localPath?.startsWith(cloneParent)
      );
      setActiveView("all");
      setQuery("");
      if (imported) setSelectedId(imported.id);
      setShowClone(false);
      setCloneUrl("");
      setCloneAutoDetected(false);
      notify(`Clone repository thành công.${autoFocusSuffix(autoFocus.focusedRepositoryIds.length)}`);
    } catch (error) {
      notify(asError(error), "error");
    } finally {
      setWorking(null);
    }
  };

  const saveSettings = async (settings: Settings) => {
    try {
      const next = await api.saveSettings(settings);
      setData(next);
    } catch (error) {
      notify(asError(error), "error");
    }
  };

  const removeSelected = async () => {
    if (!selected) return;
    const confirmed = window.confirm(
      `Xóa “${selected.name}” khỏi RepoFocus?\n\nSource code trên máy sẽ không bị xóa.`
    );
    if (!confirmed) return;
    try {
      const next = await api.removeRepository(selected.id);
      setData(next);
      setSelectedId(next.repositories[0]?.id ?? null);
      notify("Đã xóa khỏi RepoFocus.");
    } catch (error) {
      notify(asError(error), "error");
    }
  };

  const activeMeta =
    activeView === "settings"
      ? { id: "settings" as const, label: "Cài đặt", icon: SettingsIcon }
      : VIEWS.find((view) => view.id === activeView)!;

  return (
    <div className="app-shell">
      <button
        className="mobile-menu"
        aria-label="Mở menu"
        onClick={() => setSidebarOpen((open) => !open)}
      >
        <Menu size={19} />
      </button>

      <aside className={`sidebar ${sidebarOpen ? "open" : ""}`}>
        <div className="brand">
          <div className="brand-mark"><Focus size={21} strokeWidth={2.3} /></div>
          <div>
            <strong>RepoFocus</strong>
          </div>
        </div>

        <nav className="nav-list">
          {VIEWS.map((view) => {
            const Icon = view.icon;
            return (
              <button
                key={view.id}
                className={`nav-item ${activeView === view.id ? "active" : ""}`}
                onClick={() => {
                  setActiveView(view.id);
                  setQuery("");
                  setSidebarOpen(false);
                }}
              >
                <span className="nav-icon"><Icon size={17} /></span>
                <span>{view.label}</span>
                {counts[view.id] > 0 && <em>{counts[view.id]}</em>}
              </button>
            );
          })}
        </nav>

        <div className="sidebar-spacer" />
        <button
          className={`nav-item ${activeView === "settings" ? "active" : ""}`}
          onClick={() => {
            setActiveView("settings");
            setQuery("");
          }}
        >
          <span className="nav-icon"><SettingsIcon size={17} /></span>
          <span>Cài đặt</span>
        </button>
        <div className="connection-card">
          <span className={`connection-dot ${data.lastSyncAt ? "online" : ""}`} />
          <div>
            <strong>{data.lastSyncAt ? "Đã kết nối GitHub" : "Không gian cục bộ"}</strong>
            {data.lastSyncAt && <span>Đồng bộ {relativeDate(data.lastSyncAt)}</span>}
          </div>
        </div>
      </aside>

      <main className="main-pane">
        <header className="page-header">
          <div>
            <h1>{activeMeta.label}</h1>
            <span className="page-subtitle">
              {activeView === "focus"
                ? "Những repository quan trọng nhất lúc này"
                : activeView === "activity"
                  ? "Push, commit và thay đổi theo từng branch"
                : activeView === "attention"
                  ? "Các task đã quá hạn nhưng vẫn chưa hoàn thành"
                : activeView === "done"
                  ? "Các repository đã hoàn tất"
                  : activeView === "settings"
                    ? "Kết nối, giao diện và dữ liệu local"
                    : "Repository từ GitHub, GitLab và các nguồn Git đã thêm"}
            </span>
          </div>
          {activeView !== "settings" && activeView !== "activity" && (
          <div className="header-actions">
            <button className="icon-button" title="Clone repository" onClick={openCloneDialog}>
              <Download size={17} />
            </button>
            <label className="search-box">
              <Search size={16} />
              <input
                ref={searchRef}
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Tìm repo"
              />
              {query && (
                <button type="button" onClick={() => setQuery("")} aria-label="Xóa tìm kiếm">
                  <X size={13} />
                </button>
              )}
            </label>
            <button className="icon-button" title="Đồng bộ GitHub" onClick={syncGitHub} disabled={working === "sync"}>
              {working === "sync" ? <LoaderCircle className="spin" size={17} /> : <RefreshCw size={17} />}
            </button>
          </div>
          )}
        </header>

        {activeView === "focus" ? (
          loading ? (
            <section className="repo-list"><LoadingList /></section>
          ) : (
            <FocusDashboard
              repositories={repositories}
              selectedId={selectedId}
              onSelect={setSelectedId}
              onUpdateRepository={updateRepository}
            />
          )
        ) : activeView === "activity" ? (
          <ActivityView
            date={activityDate}
            setDate={setActivityDate}
            activity={activityCommits}
            loading={working === "activity"}
            onRefresh={refreshActivity}
          />
        ) : activeView === "settings" ? (
          <SettingsPage settings={data.settings} onSave={saveSettings} />
        ) : (
        <section className="repo-list" aria-label="Danh sách repository">
          {loading ? (
            <LoadingList />
          ) : repositories.length === 0 ? (
            <EmptyState view={activeView} query={query} />
          ) : (
            repositories.map((repository) => (
              <RepoRow
                key={repository.id}
                repository={repository}
                selected={repository.id === selectedId}
                showProgress={false}
                showDeadline={activeView === "attention"}
                onSelect={() => setSelectedId(repository.id)}
              />
            ))
          )}
        </section>
        )}
      </main>

      <aside className="inspector">
        {activeView === "settings" ? (
          <InspectorPlaceholder
            icon={<ShieldCheck size={38} />}
            title="Local-first ngay từ thiết kế"
            copy="Trạng thái tập trung, tiến độ và ghi chú chỉ được lưu trên máy Windows này."
          />
        ) : activeView === "activity" ? (
          <InspectorPlaceholder
            icon={<BarChart3 size={38} />}
            title="Tổng quan theo ngày"
            copy="Chọn một ngày để xem commit và thay đổi của từng repository, branch."
          />
        ) : selected ? (
          <>
            <div className="inspector-scroll">
              <div className="repo-identity">
                <div className={`repo-icon large status-${selected.tracking.status} ${selected.isPrivate ? "private" : ""}`}>
                  {selected.isPrivate ? <Lock size={22} /> : <FolderGit2 size={23} />}
                  {repositoryIsCompleted(selected) && (
                    <span className="completion-mark" title="Đã hoàn thành">
                      <CheckCircle2 size={15} fill="currentColor" />
                    </span>
                  )}
                </div>
                <div className="identity-copy">
                  <div className="identity-title-line">
                    <h2>{selected.name}</h2>
                    {repositoryIsCompleted(selected) && <CheckCircle2 className="identity-complete" size={16} fill="currentColor" />}
                  </div>
                  <div className="identity-provider-row">
                    <span className="provider-chip">
                      {selected.provider.toLowerCase().includes("github") ? <Github size={12} /> : <GitBranch size={12} />}
                      {providerTitle(selected.provider)}
                    </span>
                    <span>{selected.fullName}</span>
                  </div>
                </div>
              </div>
              {selected.description && <p className="repo-description">{selected.description}</p>}
              <div className="identity-actions">
                {selected.url && (
                  <button className="secondary-button" onClick={() => openUrl(selected.url!)}>
                    <ExternalLink size={16} />
                    {selected.provider.toLowerCase().includes("github")
                      ? "Mở trên GitHub"
                      : selected.provider.toLowerCase().includes("gitlab")
                        ? "Mở trên GitLab"
                        : "Mở nguồn repo"}
                  </button>
                )}
                {selected.tracking.isFocused && activeView !== "focus" ? (
                  <span className="focus-state"><CheckCircle2 size={16} fill="currentColor" /> Đang tập trung</span>
                ) : (
                  <button
                    className={`focus-button ${selected.tracking.isFocused ? "remove" : "add"}`}
                    onClick={() => void toggleRepositoryFocus(selected)}
                  >
                    {selected.tracking.isFocused ? <EyeOff size={16} /> : <Plus size={16} />}
                    {selected.tracking.isFocused ? "Bỏ khỏi tập trung" : "Thêm vào tập trung"}
                  </button>
                )}
              </div>

              {selected.tracking.localPath && selected.tracking.gitStatus && (
                <section className="workspace-panel">
                  <div className="workspace-heading">
                    <div>
                      <strong>Git workspace</strong>
                      <span><GitBranch size={13} /> {selected.tracking.gitStatus?.branch ?? "Detached HEAD"}</span>
                    </div>
                    <button className="icon-button" title="Kiểm tra Git" onClick={refreshGit} disabled={working === "git"}>
                      {working === "git" ? <LoaderCircle className="spin" size={16} /> : <RefreshCw size={16} />}
                    </button>
                  </div>
                  <button className="workspace-codex-button" onClick={openCodexTask} disabled={workspaceBusy}>
                    <Zap size={14} />
                    <span>Mở tác vụ mới trong Codex</span>
                    <ExternalLink size={12} />
                  </button>
                  <div className="workspace-actions">
                    <button onClick={() => openWorkspaceDialog("switch")} disabled={workspaceBusy}>
                      <ArrowLeftRight size={15} /> Đổi branch
                    </button>
                    <button onClick={() => openWorkspaceDialog("commit")} disabled={workspaceBusy}>
                      <CheckCircle2 size={15} /> Commit
                    </button>
                    <button onClick={() => executeGitAction("pull")} disabled={workspaceBusy}>
                      <Download size={15} /> Pull
                    </button>
                    <button onClick={() => executeGitAction("push")} disabled={workspaceBusy}>
                      <Upload size={15} /> Push
                    </button>
                    <button onClick={() => openWorkspaceDialog("merge")} disabled={workspaceBusy}>
                      <GitMerge size={15} /> Merge branch
                    </button>
                    <button onClick={() => openWorkspaceDialog("history")} disabled={workspaceBusy}>
                      <History size={15} /> Lịch sử commit
                    </button>
                  </div>
                  {workspaceHasConflict && (
                    <button
                      className="workspace-conflict-button"
                      onClick={() => {
                        setConfirmConflictAbort(false);
                        setShowConflictResolver(true);
                      }}
                      disabled={workspaceBusy}
                    >
                      <AlertTriangle size={15} />
                      <span>{conflictState!.files.length
                        ? `Xử lý ${conflictState!.files.length} file conflict`
                        : "Hoàn tất thao tác Git đang chờ"}</span>
                      <ArrowRight size={13} />
                    </button>
                  )}
                  <p className="workspace-safety-copy">
                    Các nút chạy Git thật trong đúng thư mục repo. Pull chỉ fast-forward; hoàn tác luôn tạo commit mới, không dùng reset --hard.
                  </p>
                </section>
              )}

              <InspectorSection title="Theo dõi">
                {selected.tracking.isFocused && (
                  <div className="focus-branch-field">
                    <span>Nhánh tập trung</span>
                    <FocusControlSelect
                      value={selected.tracking.focusBranch ?? repositoryBranch(selected) ?? "main"}
                      onChange={setFocusBranch}
                      searchable
                      ariaLabel="Chọn nhánh tập trung"
                      options={(availableBranches(selected).length
                        ? availableBranches(selected)
                        : [repositoryBranch(selected) ?? "main"]
                      ).map((branch) => ({
                        value: branch,
                        label: branch,
                        icon: <GitBranch size={14} />
                      }))}
                    />
                    <small>Nhánh được ưu tiên khi xem Focus.</small>
                  </div>
                )}
                <FieldRow label="Trạng thái">
                  <FocusControlSelect
                    value={selected.tracking.status}
                    ariaLabel="Chọn trạng thái"
                    onChange={(value) =>
                      updateSelected((repository) => ({
                        ...repository,
                        tracking: { ...repository.tracking, status: value as WorkStatus }
                      }))
                    }
                    options={Object.entries(STATUS_LABELS).map(([value, label]) => {
                      const Icon = statusIcon(value as WorkStatus);
                      return { value, label, icon: <Icon size={14} /> };
                    })}
                  />
                </FieldRow>
                <FieldRow label="Ưu tiên">
                  <div className="segmented">
                    {(Object.keys(PRIORITY_LABELS) as Priority[]).map((priority) => (
                      <button
                        key={priority}
                        className={`${selected.tracking.priority === priority ? "active " : ""}priority-${priority}`}
                        onClick={() =>
                          updateSelected((repository) => ({
                            ...repository,
                            tracking: { ...repository.tracking, priority }
                          }))
                        }
                      >
                        {PRIORITY_LABELS[priority]}
                      </button>
                    ))}
                  </div>
                </FieldRow>
                {activeView === "focus" && (
                  <div
                    className="inspector-progress"
                    style={{ "--progress-color": progressTint(selectedProgress) } as React.CSSProperties}
                  >
                    <div className="progress-heading">
                      <span>Tiến độ</span>
                      <strong>{selectedProgress}%</strong>
                    </div>
                    {selected.isArchived || selected.tracking.status === "done" || selected.tracking.status === "archived" ? (
                      <span className="progress-static-bar"><i style={{ width: "100%" }} /></span>
                    ) : selected.tracking.usesOutlinePlan ? (
                      <span className="outline-progress-bar"><i style={{ width: `${selectedProgress}%` }} /></span>
                    ) : (
                      <input
                        className="progress-slider"
                        type="range"
                        min="0"
                        max="100"
                        step="5"
                        value={selectedProgress}
                        style={{
                          "--progress": `${selectedProgress}%`,
                          "--progress-color": progressTint(selectedProgress)
                        } as React.CSSProperties}
                        onChange={(event) =>
                          updateSelected((repository) => ({
                            ...repository,
                            tracking: { ...repository.tracking, progress: Number(event.target.value) }
                          }))
                        }
                      />
                    )}
                  </div>
                )}
              </InspectorSection>

              <InspectorSection title="Kế hoạch">
                <label className="stacked-field">
                  <span>Việc tiếp theo</span>
                  <input
                    value={selected.tracking.nextAction}
                    onChange={(event) =>
                      updateSelected((repository) => ({
                        ...repository,
                        tracking: { ...repository.tracking, nextAction: event.target.value }
                      }))
                    }
                    placeholder="Bước tiếp theo để đẩy repo tiến lên"
                  />
                </label>
                {selected.tracking.isFocused && (
                  <div className="plan-mode-field">
                    <span>Cách theo dõi tiến độ</span>
                    <div className="plan-mode-control">
                      <button
                        className={!selected.tracking.usesOutlinePlan ? "active" : ""}
                        onClick={() => setOutlinePlan(false)}
                      ><BarChart3 size={13} /> Phần trăm</button>
                      <button
                        className={selected.tracking.usesOutlinePlan ? "active" : ""}
                        onClick={() => setOutlinePlan(true)}
                      ><CheckCircle2 size={13} /> Outline công việc</button>
                    </div>
                    {selected.tracking.usesOutlinePlan && (
                      <div className="outline-editor">
                        <div className="outline-editor-heading">
                          <strong>Outline công việc</strong>
                          <span>{planCompletionSummary(selected).completed}/{planCompletionSummary(selected).total} hoàn thành</span>
                        </div>
                        {selected.tracking.planItems.length ? (
                          <div className="plan-item-list">
                            {selected.tracking.planItems.map((item) => (
                              <div className={`plan-item ${item.isCompleted ? "completed" : ""}`} key={item.id}>
                                <button
                                  className="plan-item-check"
                                  aria-label={item.isCompleted ? "Đánh dấu chưa hoàn thành" : "Đánh dấu hoàn thành"}
                                  onClick={() => updatePlanItem(item.id, (current) => ({
                                    ...current,
                                    isCompleted: !current.isCompleted,
                                    completionSource: !current.isCompleted ? "manual" : null,
                                    matchedCommitSha: null,
                                    completedAt: !current.isCompleted ? new Date().toISOString() : null
                                  }))}
                                >
                                  {item.isCompleted && <Check size={11} />}
                                </button>
                                <div className="plan-item-copy">
                                  <strong>{item.title}</strong>
                                  <span>{item.isCompleted
                                    ? item.completionSource === "commit" ? "Hoàn thành từ commit" : "Đã tick thủ công"
                                    : `Chờ commit chứa “${item.commitKeyword}”`}</span>
                                  <select
                                    aria-label={`Ước lượng cho ${item.title}`}
                                    value={item.estimatedMinutes ?? ""}
                                    onChange={(event) => updatePlanItem(item.id, (current) => ({
                                      ...current,
                                      estimatedMinutes: event.target.value ? Number(event.target.value) : null
                                    }))}
                                  >
                                    <option value="">Không ước lượng</option>
                                    <option value="15">15 phút</option>
                                    <option value="30">30 phút</option>
                                    <option value="60">1 giờ</option>
                                  </select>
                                </div>
                                <button className="plan-item-remove" onClick={() => removePlanItem(item.id)} aria-label="Xóa việc">
                                  <X size={13} />
                                </button>
                              </div>
                            ))}
                          </div>
                        ) : (
                          <p className="outline-empty"><CheckCircle2 size={15} /> Thêm từng việc để theo dõi tiến độ của repo.</p>
                        )}
                        <div className="outline-add-row">
                          <input
                            value={newPlanItemTitle}
                            onChange={(event) => setNewPlanItemTitle(event.target.value)}
                            onKeyDown={(event) => {
                              if (event.key === "Enter") {
                                event.preventDefault();
                                addPlanItem();
                              }
                            }}
                            placeholder="Tên việc hoặc cụm từ trong commit"
                          />
                          <button onClick={addPlanItem} disabled={!newPlanItemTitle.trim()} aria-label="Thêm việc"><Plus size={15} /></button>
                        </div>
                        <p className="outline-help">Bạn có thể tick thủ công và đặt cụm từ để đối chiếu với commit.</p>
                      </div>
                    )}
                  </div>
                )}
                <button
                  type="button"
                  className={`deadline-enabled${selected.tracking.deadline ? " active" : ""}`}
                  role="checkbox"
                  aria-checked={Boolean(selected.tracking.deadline)}
                  onClick={() =>
                    updateSelected((repository) => ({
                      ...repository,
                      tracking: {
                        ...repository.tracking,
                        deadline: repository.tracking.deadline ? null : localISODate(new Date(Date.now() + 7 * 86_400_000))
                      }
                    }))
                  }
                >
                  <span className="deadline-check">{selected.tracking.deadline ? <Check size={13} /> : null}</span>
                  <span>Đặt hạn hoàn thành</span>
                </button>
                {selected.tracking.deadline ? (
                  <div className="deadline-row">
                    <span>Hạn chót</span>
                    <RepoDatePicker
                      className="deadline-date-picker"
                      value={selected.tracking.deadline}
                      placeholder="Chọn hạn chót"
                      onChange={(deadline) =>
                        updateSelected((repository) => ({
                          ...repository,
                          tracking: { ...repository.tracking, deadline }
                        }))
                      }
                    />
                  </div>
                ) : null}
              </InspectorSection>

              <InspectorSection title="Git trên máy">
                <p className="inspector-field-label">Thư mục repo đã clone</p>
                <p className="inspector-help">
                  RepoFocus dùng thư mục này để đọc trạng thái commit, push và conflict trên máy Windows.
                </p>
                <label className="local-path-input">
                  <Folder size={16} />
                  <input
                    value={selected.tracking.localPath ?? ""}
                    onChange={(event) => {
                      setLocalDetection("idle");
                      updateSelected((repository) => ({
                        ...repository,
                        tracking: { ...repository.tracking, localPath: event.target.value || null, gitStatus: null }
                      }));
                    }}
                    placeholder="Dán đường dẫn thư mục repo"
                  />
                </label>
                <div className="local-git-actions">
                  {selected.tracking.localPath ? (
                    <button className="secondary-button" onClick={refreshGit} disabled={working === "git"}>
                      {working === "git" ? <LoaderCircle className="spin" size={15} /> : <RefreshCw size={15} />}
                      Kiểm tra Git
                    </button>
                  ) : (
                    <button className="secondary-button" onClick={autoDetectLocalRepository} disabled={localDetection === "searching"}>
                      {localDetection === "searching" ? <LoaderCircle className="spin" size={15} /> : <Search size={16} />}
                      {localDetection === "searching" ? "Đang tìm…" : "Tự tìm trên máy"}
                    </button>
                  )}
                  {selected.tracking.gitStatus?.checkedAt && (
                    <span>Kiểm tra {relativeDate(selected.tracking.gitStatus.checkedAt)}</span>
                  )}
                </div>
                {selected.tracking.localPath ? (
                  <GitStatusCard status={selected.tracking.gitStatus} />
                ) : (
                  <div className="local-git-empty">
                    <FolderGit2 size={20} />
                    <div>
                      <strong>{localDetection === "not-found" ? "Không tìm thấy checkout khớp trên máy" : "Chưa tìm thấy checkout trên máy"}</strong>
                      <span>{localDetection === "not-found" ? "Bạn vẫn có thể dán đường dẫn thủ công hoặc chọn thư mục ở màn hình thêm repo." : "Bạn vẫn có thể dán đường dẫn thủ công."}</span>
                    </div>
                  </div>
                )}
              </InspectorSection>

              <InspectorSection title="Thông tin repo">
                <div className="repository-metadata">
                  <MetadataRow label="Ngôn ngữ" value={selected.primaryLanguage ?? "—"} />
                  <MetadataRow label="Nhánh mặc định" value={selected.defaultBranch ?? "—"} />
                  <MetadataRow label="Issue đang mở" value={String(selected.openIssueCount)} />
                  <MetadataRow label="Pull request đang mở" value={String(selected.openPullRequestCount)} />
                  <MetadataRow label="Lần push gần nhất" value={selected.pushedAt ? relativeDate(selected.pushedAt) : "—"} />
                </div>
              </InspectorSection>

              <InspectorSection title="Ghi chú">
                <label className="stacked-field notes-field">
                  <textarea
                    rows={4}
                    value={selected.tracking.notes}
                    onChange={(event) =>
                      updateSelected((repository) => ({
                        ...repository,
                        tracking: { ...repository.tracking, notes: event.target.value }
                      }))
                    }
                    placeholder="Ghi lại bối cảnh, quyết định hoặc điều cần nhớ…"
                  />
                </label>
              </InspectorSection>
            </div>
          </>
        ) : (
          <div className="no-selection">
            <Box size={34} />
            <strong>Chọn một repository</strong>
            <span>Thông tin và kế hoạch sẽ xuất hiện tại đây.</span>
          </div>
        )}
      </aside>

      {showClone && (
        <Modal title="Clone repository" onClose={() => setShowClone(false)}>
          {cloneAutoDetected ? (
            <>
              <p className="modal-copy">
                Clone <strong>{selected?.fullName ?? selected?.name}</strong> về máy. Chỉ cần chọn thư mục lưu.
              </p>
              <label className="stacked-field">
                <span>Git URL</span>
                <input value={cloneUrl} readOnly />
              </label>
            </>
          ) : (
            <>
              <p className="modal-copy">Clone từ GitHub, GitLab hoặc bất kỳ Git remote HTTPS/SSH nào.</p>
              <label className="stacked-field">
                <span>Git URL</span>
                <input
                  autoFocus
                  value={cloneUrl}
                  onChange={(event) => setCloneUrl(event.target.value)}
                  placeholder="https://github.com/owner/repository.git"
                />
              </label>
            </>
          )}
          <label className="stacked-field">
            <span>Thư mục lưu</span>
            <button className="path-picker" autoFocus={cloneAutoDetected} onClick={chooseCloneParent}>
              <Folder size={16} />
              <span>{cloneParent || "Chọn thư mục cha..."}</span>
            </button>
          </label>
          <div className="modal-actions">
            <button className="secondary-button" onClick={() => setShowClone(false)}>Hủy</button>
            <button className="primary-button" onClick={clone} disabled={working === "clone"}>
              {working === "clone" ? <LoaderCircle className="spin" size={16} /> : <Download size={16} />}
              Clone
            </button>
          </div>
        </Modal>
      )}

      {workspaceDialog === "switch" && selected && (
        <Modal title="Đổi branch" onClose={() => setWorkspaceDialog(null)} dismissible={!workspaceBusy}>
          <p className="modal-copy">
            Chuyển working directory sang branch khác. Nhánh hiện tại là <strong>{selected.tracking.gitStatus?.branch ?? repositoryBranch(selected) ?? "Detached HEAD"}</strong>.
          </p>
          <label className="stacked-field">
            <span>Chuyển sang branch</span>
            <select autoFocus value={workspaceBranch} onChange={(event) => setWorkspaceBranch(event.target.value)}>
              {switchBranchOptions(selected)
                .map((branch) => <option key={branch} value={branch}>{branch}</option>)}
            </select>
          </label>
          {!workspaceBranch && <p className="workspace-dialog-empty">Không có branch phù hợp. Hãy kiểm tra Git để tải lại danh sách.</p>}
          <div className="modal-actions">
            <button className="secondary-button" onClick={() => setWorkspaceDialog(null)} disabled={workspaceBusy}>Hủy</button>
            <button
              className="primary-button"
              onClick={() => void executeWorkspaceAction("switch", workspaceBranch)}
              disabled={!workspaceBranch || workspaceBusy}
            >
              {working === "workspace-switch" ? <LoaderCircle className="spin" size={16} /> : <ArrowLeftRight size={16} />}
              Chuyển branch
            </button>
          </div>
        </Modal>
      )}

      {workspaceDialog === "commit" && selected && (
        <Modal title="Tạo commit" onClose={() => setWorkspaceDialog(null)} dismissible={!workspaceBusy}>
          <p className="modal-copy">
            Commit toàn bộ thay đổi đang có trên branch <strong>{selected.tracking.gitStatus?.branch ?? repositoryBranch(selected) ?? "hiện tại"}</strong>.
          </p>
          <label className="stacked-field workspace-commit-message">
            <span>Nội dung commit</span>
            <textarea
              autoFocus
              rows={5}
              value={workspaceCommitMessage}
              onChange={(event) => setWorkspaceCommitMessage(event.target.value)}
              placeholder="Mô tả thay đổi đã hoàn thành…"
            />
          </label>
          <p className="workspace-dialog-note">RepoFocus sẽ stage file mới, đã sửa và đã xóa bằng <code>git add -A</code>.</p>
          <div className="modal-actions">
            <button className="secondary-button" onClick={() => setWorkspaceDialog(null)} disabled={workspaceBusy}>Hủy</button>
            <button
              className="primary-button"
              onClick={() => void executeWorkspaceAction("commit", workspaceCommitMessage)}
              disabled={!workspaceCommitMessage.trim() || workspaceBusy}
            >
              {working === "workspace-commit" ? <LoaderCircle className="spin" size={16} /> : <CheckCircle2 size={16} />}
              Commit toàn bộ
            </button>
          </div>
        </Modal>
      )}

      {workspaceDialog === "merge" && selected && (
        <Modal title="Merge branch" onClose={() => setWorkspaceDialog(null)} dismissible={!workspaceBusy}>
          <p className="modal-copy">
            Nhập branch được chọn vào <strong>{selected.tracking.gitStatus?.branch ?? repositoryBranch(selected) ?? "branch hiện tại"}</strong>.
          </p>
          <label className="stacked-field">
            <span>Branch cần merge</span>
            <select autoFocus value={workspaceBranch} onChange={(event) => setWorkspaceBranch(event.target.value)}>
              {mergeBranchOptions(selected)
                .map((branch) => <option key={branch} value={branch}>{branch}</option>)}
            </select>
          </label>
          {!workspaceBranch ? (
            <p className="workspace-dialog-empty">Không có branch phù hợp. Hãy kiểm tra Git để tải lại danh sách.</p>
          ) : (
            <p className="workspace-dialog-note">Nếu hai branch sửa cùng vùng code, Git sẽ yêu cầu xử lý conflict trước khi hoàn tất.</p>
          )}
          <div className="modal-actions">
            <button className="secondary-button" onClick={() => setWorkspaceDialog(null)} disabled={workspaceBusy}>Hủy</button>
            <button
              className="primary-button"
              onClick={() => void executeWorkspaceAction("merge", workspaceBranch)}
              disabled={!workspaceBranch || workspaceBusy}
            >
              {working === "workspace-merge" ? <LoaderCircle className="spin" size={16} /> : <GitMerge size={16} />}
              Merge vào branch hiện tại
            </button>
          </div>
        </Modal>
      )}

      {workspaceDialog === "history" && selected && (
        <Modal title="Lịch sử commit" className="history-modal" onClose={() => setWorkspaceDialog(null)} dismissible={!workspaceBusy}>
          <p className="modal-copy">
            Hoàn tác an toàn bằng một commit mới trên branch <strong>{selected.tracking.gitStatus?.branch ?? repositoryBranch(selected) ?? "hiện tại"}</strong>.
          </p>
          {working === "workspace-history" ? (
            <div className="workspace-history-loading"><LoaderCircle className="spin" size={18} /> Đang đọc lịch sử commit…</div>
          ) : (
            <CommitList
              commits={commits}
              pendingRevertSha={pendingRevertSha}
              reverting={working === "workspace-revert"}
              onRequestRevert={setPendingRevertSha}
              onCancelRevert={() => setPendingRevertSha(null)}
              onConfirmRevert={(sha) => void executeWorkspaceAction("revert", sha)}
            />
          )}
          <div className="history-modal-footer">
            <span>Lịch sử đã push không bị viết lại.</span>
            <button className="secondary-button" onClick={() => setWorkspaceDialog(null)} disabled={workspaceBusy}>Đóng</button>
          </div>
        </Modal>
      )}

      {showConflictResolver && selected && conflictState && (
        <Modal
          title="Xử lý conflict"
          className="conflict-modal"
          onClose={() => {
            if (!workspaceBusy) setShowConflictResolver(false);
          }}
          dismissible={!workspaceBusy}
        >
          <p className="modal-copy">
            {conflictState.files.length
              ? "Chọn cách xử lý cho từng file. RepoFocus sẽ stage file đã chọn, sau đó bạn hoàn tất thao tác Git."
              : conflictState.sequence === "merge"
                ? "Mọi file đã được xử lý. Bạn có thể hoàn tất merge."
                : "Mọi file đã được xử lý. Bạn có thể hoàn tất hoàn tác."}
          </p>
          {conflictState.files.length ? (
            <div className="conflict-file-list">
              {conflictState.files.map((file) => (
                <div className="conflict-file" key={file}>
                   <code>{file}</code>
                   <div>
                      <button
                        className="secondary-button"
                        onClick={() => void openConflictFile(file)}
                        disabled={workspaceBusy}
                      >Mở file</button>
                      <button
                      className="secondary-button"
                      onClick={() => void executeConflictAction("resolve", file, "ours")}
                      disabled={workspaceBusy}
                    >Giữ bản hiện tại</button>
                    <button
                      className="secondary-button"
                      onClick={() => void executeConflictAction("resolve", file, "theirs")}
                      disabled={workspaceBusy}
                    >Dùng bản branch nhập</button>
                    <button
                      className="secondary-button"
                      onClick={() => void executeConflictAction("resolve", file, "markResolved")}
                      disabled={workspaceBusy}
                    >Đã tự xử lý</button>
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <div className="conflict-clear-state"><CheckCircle2 size={18} /> Không còn file conflict.</div>
          )}
          {conflictState.sequence !== "none" && (
            <div className="conflict-operation-actions">
              {!conflictState.files.length && (
                <button
                  className="primary-button"
                  onClick={() => void executeConflictAction("continue")}
                  disabled={workspaceBusy}
                >
                  {working === "workspace-continue-conflict" ? <LoaderCircle className="spin" size={16} /> : <CheckCircle2 size={16} />}
                  {conflictState.sequence === "merge" ? "Hoàn tất merge" : "Hoàn tất hoàn tác"}
                </button>
              )}
              {confirmConflictAbort ? (
                <div className="conflict-abort-confirmation">
                  <p>Hủy {conflictState.sequence === "merge" ? "merge" : "hoàn tác"} đang chờ? Các commit đã tồn tại trước đó không bị thay đổi.</p>
                  <div>
                    <button className="secondary-button" onClick={() => setConfirmConflictAbort(false)} disabled={workspaceBusy}>Quay lại</button>
                    <button
                      className="commit-revert-confirm"
                      onClick={() => void executeConflictAction("abort")}
                      disabled={workspaceBusy}
                    >
                      {working === "workspace-abort-conflict" ? <LoaderCircle className="spin" size={14} /> : <X size={14} />}
                      Hủy thao tác
                    </button>
                  </div>
                </div>
              ) : (
                <button className="workspace-abort-button" onClick={() => setConfirmConflictAbort(true)} disabled={workspaceBusy}>
                  <X size={14} /> Hủy {conflictState.sequence === "merge" ? "merge" : "hoàn tác"}
                </button>
              )}
            </div>
          )}
          <div className="history-modal-footer">
            <span>Không dùng reset --hard.</span>
            <button className="secondary-button" onClick={() => setShowConflictResolver(false)} disabled={workspaceBusy}>Đóng</button>
          </div>
        </Modal>
      )}

      {toast && (
        <div className={`toast ${toast.tone}`} role="alert" aria-live="assertive">
          {toast.tone === "ok" ? <Check size={17} /> : <AlertTriangle size={17} />}
          <span>{toast.text}</span>
          <button onClick={() => setToast(null)}><X size={15} /></button>
        </div>
      )}
    </div>
  );
}

function InspectorSection({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="inspector-section">
      <h3>{title}</h3>
      {children}
    </section>
  );
}

function FocusDashboard({
  repositories,
  selectedId,
  onSelect,
  onUpdateRepository
}: {
  repositories: Repository[];
  selectedId: string | null;
  onSelect: (id: string) => void;
  onUpdateRepository: (
    repositoryId: string,
    update: (repository: Repository) => Repository,
    saveImmediately?: boolean
  ) => void;
}) {
  const [expandedPlannerId, setExpandedPlannerId] = useState<string | null>(null);
  const attention = [...repositories]
    .filter(needsAttention)
    .sort((left, right) => {
      const leftDeadline = left.tracking.deadline ?? "9999-12-31";
      const rightDeadline = right.tracking.deadline ?? "9999-12-31";
      if (leftDeadline !== rightDeadline) return leftDeadline.localeCompare(rightDeadline);
      const priority = { high: 0, medium: 1, low: 2 };
      const priorityDifference = priority[left.tracking.priority] - priority[right.tracking.priority];
      if (priorityDifference) return priorityDifference;
      return left.tracking.focusOrder - right.tracking.focusOrder;
    });
  const overdueTaskTotal = attention.reduce(
    (total, repository) => total + overdueTaskCount(repository),
    0
  );
  const active = repositories.filter((repo) => repo.tracking.status === "active").length;
  const blocked = repositories.filter((repo) => repo.tracking.status === "blocked").length;
  const openPullRequests = repositories.reduce(
    (total, repository) => total + repository.openPullRequestCount,
    0
  );

  if (!repositories.length) {
    return (
      <section className="repo-list">
        <EmptyState view="focus" query="" />
      </section>
    );
  }

  return (
    <section className="focus-dashboard">
      {attention.length > 0 && (
        <div className="attention-panel">
          <div className="attention-header">
            <div className="metric-icon amber"><Bell size={19} fill="currentColor" /></div>
            <div>
              <strong>Task quá hạn chưa hoàn thành</strong>
              <span>Chỉ hiển thị task đã quá hạn nhưng chưa hoàn thành.</span>
            </div>
            <em>{overdueTaskTotal} task</em>
          </div>
          {attention.slice(0, 4).map((repository) => {
            const ReminderIcon = focusReminderIcon(repository);
            const branch = repositoryBranch(repository);
            const canOpenPlanner = focusReminderKind(repository) === "next" && !repository.tracking.nextAction.trim();
            const isExpanded = expandedPlannerId === repository.id;
            return (
              <div className={`attention-reminder ${isExpanded ? "expanded" : ""}`} key={repository.id}>
                <button
                  onClick={() => {
                    if (canOpenPlanner || isExpanded) {
                      setExpandedPlannerId((current) => current === repository.id ? null : repository.id);
                    } else {
                      onSelect(repository.id);
                    }
                  }}
                >
                  <span className={`mini-focus-icon reminder-${focusReminderKind(repository)}`}><ReminderIcon size={14} /></span>
                  <strong>{repository.name}</strong>
                  {branch && <span className="mini-branch"><GitBranch size={12} /> {branch}</span>}
                  <span>{focusReminderLabel(repository)}</span>
                  <ChevronDown className={isExpanded ? "expanded" : ""} size={14} />
                </button>
                {isExpanded && (
                  <FocusReminderPlanner
                    repository={repository}
                    onClose={() => setExpandedPlannerId(null)}
                    onUpdateRepository={onUpdateRepository}
                  />
                )}
              </div>
            );
          })}
          {attention.length > 4 && (
            <p className="attention-more">VÃ  {attention.length - 4} repository khÃ¡c trong danh sÃ¡ch táº­p trung</p>
          )}
        </div>
      )}

      <div className="focus-stats">
        <MetricCard icon={<Zap size={18} fill="currentColor" />} tone="blue" value={active} label="Đang làm" />
        <MetricCard icon={<AlertTriangle size={18} fill="currentColor" />} tone="red" value={blocked} label="Bị chặn" />
        <MetricCard icon={<GitPullRequest size={18} />} tone="purple" value={openPullRequests} label="Pull request" />
      </div>

      <div className="focus-list-panel">
        <div className="panel-heading">
          <strong>Đang tập trung</strong>
          <span>{repositories.length} repository</span>
        </div>
        {repositories.map((repository) => (
          <RepoRow
            key={repository.id}
            repository={repository}
            selected={selectedId === repository.id}
            showProgress
            showDeadline={false}
            onSelect={() => onSelect(repository.id)}
          />
        ))}
      </div>
    </section>
  );
}

function FocusReminderPlanner({
  repository,
  onClose,
  onUpdateRepository
}: {
  repository: Repository;
  onClose: () => void;
  onUpdateRepository: (
    repositoryId: string,
    update: (repository: Repository) => Repository,
    saveImmediately?: boolean
  ) => void;
}) {
  const [taskTitle, setTaskTitle] = useState("");
  const [estimatedMinutes, setEstimatedMinutes] = useState(60);
  const items = repository.tracking.planItems ?? [];
  const remainingMinutes = items
    .filter((item) => !item.isCompleted)
    .reduce((total, item) => total + (item.estimatedMinutes ?? 0), 0);

  const updateTracking = (update: (tracking: Tracking) => Tracking) => {
    onUpdateRepository(
      repository.id,
      (current) => ({ ...current, tracking: update(current.tracking) }),
      true
    );
  };

  const addTask = () => {
    const title = taskTitle.trim();
    if (!title) return;
    const item: RepositoryPlanItem = {
      id: crypto.randomUUID(),
      title,
      commitKeyword: title,
      estimatedMinutes,
      isCompleted: false,
      completionSource: null,
      matchedCommitSha: null,
      createdAt: new Date().toISOString(),
      completedAt: null
    };
    updateTracking((tracking) => {
      const next = {
        ...tracking,
        usesOutlinePlan: true,
        manualProgress: tracking.usesOutlinePlan ? tracking.manualProgress : tracking.progress,
        nextAction: tracking.nextAction.trim() ? tracking.nextAction : title,
        planItems: [...(tracking.planItems ?? []), item]
      };
      return reconcileOutlineTracking(next);
    });
    setTaskTitle("");
  };

  const toggleTask = (itemId: string) => {
    updateTracking((tracking) => reconcileOutlineTracking({
      ...tracking,
      planItems: (tracking.planItems ?? []).map((item) => item.id !== itemId ? item : {
        ...item,
        isCompleted: !item.isCompleted,
        completionSource: !item.isCompleted ? "manual" : null,
        matchedCommitSha: null,
        completedAt: !item.isCompleted ? new Date().toISOString() : null
      })
    }));
  };

  const setTaskEstimate = (itemId: string, minutes: number) => {
    updateTracking((tracking) => ({
      ...tracking,
      planItems: (tracking.planItems ?? []).map((item) => item.id === itemId ? {
        ...item,
        estimatedMinutes: minutes
      } : item)
    }));
  };

  const removeTask = (itemId: string) => {
    updateTracking((tracking) => {
      const removed = (tracking.planItems ?? []).find((item) => item.id === itemId);
      const nextAction = removed && normalizedCommitText(tracking.nextAction) === normalizedCommitText(removed.title)
        ? ""
        : tracking.nextAction;
      return reconcileOutlineTracking({
        ...tracking,
        nextAction,
        planItems: (tracking.planItems ?? []).filter((item) => item.id !== itemId)
      });
    });
  };

  return (
    <div className="focus-reminder-planner">
      <div className="focus-reminder-planner-heading">
        <div className="focus-reminder-planner-title">
          <span><BarChart3 size={14} /></span>
          <div>
            <strong>Lập danh sách công việc</strong>
            <small>Kế hoạch cho branch {repositoryBranch(repository) ?? "hiện tại"}</small>
          </div>
        </div>
        <div className="focus-reminder-planner-actions">
          {remainingMinutes > 0 && <em>{remainingMinutes < 60 ? `${remainingMinutes} phút` : `${Math.round(remainingMinutes / 60 * 10) / 10} giờ`}</em>}
          <button type="button" className="planner-close" onClick={onClose} aria-label="Đóng bảng kế hoạch"><X size={14} /></button>
        </div>
      </div>

      {items.length > 0 && (
        <div className="focus-reminder-task-list">
          {items.map((item) => (
            <div className={`focus-reminder-task ${item.isCompleted ? "completed" : ""}`} key={item.id}>
              <button type="button" className="focus-reminder-task-check" onClick={() => toggleTask(item.id)} aria-label={item.isCompleted ? "Đánh dấu chưa hoàn thành" : "Đánh dấu hoàn thành"}>
                {item.isCompleted && <Check size={11} />}
              </button>
              <strong>{item.title}</strong>
              <select value={item.estimatedMinutes ?? 60} onChange={(event) => setTaskEstimate(item.id, Number(event.target.value))} aria-label={`Ước lượng cho ${item.title}`}>
                <option value="15">15 phút</option>
                <option value="30">30 phút</option>
                <option value="60">1 giờ</option>
                <option value="120">2 giờ</option>
              </select>
              <button type="button" className="planner-remove-task" onClick={() => removeTask(item.id)} aria-label={`Xóa ${item.title}`}><X size={13} /></button>
            </div>
          ))}
        </div>
      )}

      <div className="focus-reminder-add-task">
        <input
          value={taskTitle}
          onChange={(event) => setTaskTitle(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Enter") {
              event.preventDefault();
              addTask();
            }
          }}
          placeholder="Ví dụ: Hoàn thiện màn hình đăng nhập"
        />
        <select value={estimatedMinutes} onChange={(event) => setEstimatedMinutes(Number(event.target.value))} aria-label="Ước lượng công việc mới">
          <option value="15">15 phút</option>
          <option value="30">30 phút</option>
          <option value="60">1 giờ</option>
          <option value="120">2 giờ</option>
        </select>
        <button type="button" onClick={addTask} disabled={!taskTitle.trim()}><Plus size={15} /> Thêm</button>
      </div>
      <p><CheckCircle2 size={13} /> Việc đầu tiên trở thành việc tiếp theo; commit khớp tên việc vẫn có thể tự hoàn thành.</p>
    </div>
  );
}

function MetricCard({
  icon,
  tone,
  value,
  label
}: {
  icon: React.ReactNode;
  tone: string;
  value: number;
  label: string;
}) {
  return (
    <div className="metric-card">
      <div className={`metric-icon ${tone}`}>{icon}</div>
      <div><strong>{value}</strong><span>{label}</span></div>
    </div>
  );
}

const CALENDAR_WEEKDAYS = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"];

function monthStart(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), 1, 12);
}

function dateFromLocalISO(value: string): Date {
  const [year, month, day] = value.split("-").map(Number);
  if (!year || !month || !day) return new Date();
  return new Date(year, month - 1, day, 12);
}

function RepoDatePicker({
  value,
  onChange,
  maxDate,
  className = "",
  placeholder = "Chọn ngày"
}: {
  value: string | null;
  onChange: (date: string | null) => void;
  maxDate?: string;
  className?: string;
  placeholder?: string;
}) {
  const pickerRef = useRef<HTMLDivElement>(null);
  const [isOpen, setIsOpen] = useState(false);
  const fallbackDate = value ? dateFromLocalISO(value) : new Date();
  const [displayedMonth, setDisplayedMonth] = useState(() => monthStart(fallbackDate));
  const today = localISODate();
  const selectedMonth = monthStart(fallbackDate);
  const maxMonth = maxDate ? monthStart(dateFromLocalISO(maxDate)) : null;
  const year = displayedMonth.getFullYear();
  const month = displayedMonth.getMonth();
  const leadingDays = (new Date(year, month, 1).getDay() + 6) % 7;
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const monthLabel = new Intl.DateTimeFormat("vi-VN", { month: "long", year: "numeric" }).format(displayedMonth);
  const dayText = String(fallbackDate.getDate()).padStart(2, "0");
  const monthText = String(fallbackDate.getMonth() + 1).padStart(2, "0");
  const yearText = String(fallbackDate.getFullYear());

  useEffect(() => {
    if (!isOpen) setDisplayedMonth(selectedMonth);
  }, [isOpen, selectedMonth.getFullYear(), selectedMonth.getMonth()]);

  useEffect(() => {
    if (!isOpen) return;
    const closeWhenLeaving = (event: PointerEvent) => {
      if (!pickerRef.current?.contains(event.target as Node)) setIsOpen(false);
    };
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") setIsOpen(false);
    };
    document.addEventListener("pointerdown", closeWhenLeaving);
    document.addEventListener("keydown", closeOnEscape);
    return () => {
      document.removeEventListener("pointerdown", closeWhenLeaving);
      document.removeEventListener("keydown", closeOnEscape);
    };
  }, [isOpen]);

  const moveMonth = (offset: number) => {
    setDisplayedMonth((current) => new Date(current.getFullYear(), current.getMonth() + offset, 1, 12));
  };

  const selectDate = (value: string) => {
    if (maxDate && value > maxDate) return;
    onChange(value);
    setIsOpen(false);
  };

  return (
    <div ref={pickerRef} className={["activity-date-picker", className, isOpen ? "open" : ""].filter(Boolean).join(" ")}>
      <button
        type="button"
        className="activity-date-trigger"
        aria-label={value ? "Đổi ngày" : "Chọn ngày"}
        aria-haspopup="dialog"
        aria-expanded={isOpen}
        onClick={() => setIsOpen((current) => !current)}
      >
        {value ? (
          <span className="activity-date-value" aria-hidden="true">
            <span className="date-part">{dayText}</span>
            <span className="date-separator">/</span>
            <span className="date-part">{monthText}</span>
            <span className="date-separator">/</span>
            <span className="date-year">{yearText}</span>
          </span>
        ) : <span className="date-placeholder">{placeholder}</span>}
        <i className="date-trigger-divider" aria-hidden="true" />
        <CalendarDays size={15} />
      </button>

      {isOpen ? (
        <div className="activity-calendar-popover" role="dialog" aria-label="Chọn ngày">
          <div className="calendar-popover-header">
            <button type="button" aria-label="Tháng trước" onClick={() => moveMonth(-1)}>
              <ArrowLeft size={15} />
            </button>
            <strong>{monthLabel}</strong>
            <button
              type="button"
              aria-label="Tháng sau"
              disabled={Boolean(maxMonth && displayedMonth.getTime() >= maxMonth.getTime())}
              onClick={() => moveMonth(1)}
            >
              <ArrowRight size={15} />
            </button>
          </div>
          <div className="calendar-weekdays" aria-hidden="true">
            {CALENDAR_WEEKDAYS.map((label) => <span key={label}>{label}</span>)}
          </div>
          <div className="calendar-days">
            {Array.from({ length: leadingDays }, (_, index) => <span key={`blank-${index}`} />)}
            {Array.from({ length: daysInMonth }, (_, index) => {
              const day = index + 1;
              const dateValue = localISODate(new Date(year, month, day, 12));
              const isSelected = dateValue === value;
              const isToday = dateValue === today;
              const isFuture = Boolean(maxDate && dateValue > maxDate);
              return (
                <button
                  key={dateValue}
                  type="button"
                  className={`${isSelected ? "selected " : ""}${isToday ? "today" : ""}`}
                  aria-label={`Chọn ngày ${day}`}
                  aria-pressed={isSelected}
                  disabled={isFuture}
                  onClick={() => selectDate(dateValue)}
                >
                  {day}
                </button>
              );
            })}
          </div>
        </div>
      ) : null}
    </div>
  );
}

function ActivityView({
  date,
  setDate,
  activity,
  loading,
  onRefresh
}: {
  date: string;
  setDate: (date: string) => void;
  activity: Array<{ repository: Repository; commit: CommitInfo }>;
  loading: boolean;
  onRefresh: () => void;
}) {
  const groups = useMemo(() => {
    const byRepository = new Map<string, { repository: Repository; commits: CommitInfo[] }>();
    for (const item of activity) {
      const current = byRepository.get(item.repository.id) ?? {
        repository: item.repository,
        commits: []
      };
      current.commits.push(item.commit);
      byRepository.set(item.repository.id, current);
    }
    return Array.from(byRepository.values());
  }, [activity]);
  const branches = new Set(groups.map((group) => group.repository.tracking.gitStatus?.branch ?? group.repository.defaultBranch).filter(Boolean));
  const formattedDate = new Intl.DateTimeFormat("vi-VN", {
    weekday: "long",
    day: "numeric",
    month: "long",
    year: "numeric"
  }).format(new Date(`${date}T12:00:00`));

  const moveDate = (days: number) => {
    const next = new Date(`${date}T12:00:00`);
    next.setDate(next.getDate() + days);
    setDate(next > new Date(`${localISODate()}T23:59:59`) ? localISODate() : localISODate(next));
  };

  return (
    <section className="activity-view">
      <div className="daily-summary">
        <div>
          <strong>Tổng kết ngày</strong>
          <span>{formattedDate}</span>
        </div>
        <div className="date-controls">
          <button type="button" aria-label="Ngày trước" onClick={() => moveDate(-1)}><ArrowLeft size={17} /></button>
          <RepoDatePicker
            value={date}
            maxDate={localISODate()}
            onChange={(nextDate) => { if (nextDate) setDate(nextDate); }}
          />
          <button type="button" aria-label="Ngày sau" disabled={date >= localISODate()} onClick={() => moveDate(1)}><ArrowRight size={17} /></button>
          {date !== localISODate() ? (
            <button type="button" className="date-today" onClick={() => setDate(localISODate())}>Hôm nay</button>
          ) : null}
          <button onClick={onRefresh}>{loading ? <LoaderCircle className="spin" size={17} /> : <RefreshCw size={17} />}</button>
        </div>
      </div>

      <div className="activity-stats">
        <MetricCard icon={<ArrowUpCircle size={18} />} tone="blue" value={groups.length} label="Lượt cập nhật" />
        <MetricCard icon={<GitCommitHorizontal size={18} />} tone="blue" value={activity.length} label="Commit" />
        <MetricCard icon={<GitBranch size={18} />} tone="blue" value={branches.size} label="Branch" />
        <MetricCard icon={<Box size={18} />} tone="blue" value={groups.length} label="Repository" />
      </div>
      <p className="activity-hint">Dữ liệu gồm commit local và hoạt động PushEvent mới nhất từ GitHub.</p>

      {groups.length ? (
        <div className="activity-groups">
          {groups.map(({ repository, commits }) => (
            <article className="activity-group" key={repository.id}>
              <header>
                <div>
                  <Box size={16} />
                  <strong>{repository.fullName}</strong>
                  <span className="provider-chip"><Github size={13} /> {repository.provider}</span>
                  <span className="branch-chip"><GitBranch size={12} /> {repository.tracking.gitStatus?.branch ?? repository.defaultBranch ?? "main"}</span>
                </div>
                <span>{commits.length} commit</span>
              </header>
              <div>
                {commits.map((commit) => (
                  <div className="activity-commit" key={commit.sha}>
                    <span className="commit-time">
                      {new Intl.DateTimeFormat("vi-VN", { hour: "2-digit", minute: "2-digit" }).format(new Date(commit.committedAt))}
                    </span>
                    <code>{commit.sha.slice(0, 7)}</code>
                    <strong>{commit.subject}</strong>
                    <em>{commitKind(commit.subject)}</em>
                  </div>
                ))}
              </div>
            </article>
          ))}
        </div>
      ) : (
        <div className="activity-empty">
          <BarChart3 size={31} />
          <strong>Chưa có hoạt động trong ngày này</strong>
          <span>Thêm repo local hoặc chọn một ngày khác để xem commit.</span>
        </div>
      )}
    </section>
  );
}

function commitKind(subject: string): string {
  const normalized = subject.toLowerCase();
  if (/^(fix|bug)|\bfix(e[ds])?\b/.test(normalized)) return "Fix";
  if (/^(feat|add)|\bfeature\b/.test(normalized)) return "Feature";
  if (/^(docs)|\b(readme|document)/.test(normalized)) return "Docs";
  if (/^(test)|\btests?\b/.test(normalized)) return "Test";
  if (/^(refactor)|\brefactor/.test(normalized)) return "Refactor";
  return "Commit";
}

function SettingsPage({
  settings,
  onSave
}: {
  settings: Settings;
  onSave: (settings: Settings) => void;
}) {
  return (
    <section className="settings-page">
      <div className="settings-panel">
        <div className="settings-panel-title">
          <div className="metric-icon purple"><Brush size={19} /></div>
          <div><strong>Giao diện và ngôn ngữ</strong><span>Tạo không gian làm việc phù hợp với bạn.</span></div>
        </div>
        <div className="settings-divider" />
        <label>Giao diện</label>
        <div className="choice-buttons">
          <button className={settings.theme === "system" ? "active" : ""} onClick={() => onSave({ ...settings, theme: "system" })}>
            <SlidersIcon /> Hệ thống
          </button>
          <button className={settings.theme === "light" ? "active" : ""} onClick={() => onSave({ ...settings, theme: "light" })}>
            <Sun size={15} /> Sáng
          </button>
          <button className={settings.theme === "dark" ? "active" : ""} onClick={() => onSave({ ...settings, theme: "dark" })}>
            <Moon size={15} /> Tối
          </button>
        </div>
        <label>Ngôn ngữ</label>
        <div className="choice-buttons">
          <button className={settings.language === "vi" ? "active" : ""} onClick={() => onSave({ ...settings, language: "vi" })}>Abc&nbsp;&nbsp; Tiếng Việt</button>
          <button className={settings.language === "en" ? "active" : ""} onClick={() => onSave({ ...settings, language: "en" })}>A&nbsp;&nbsp; English</button>
        </div>
      </div>

      <div className="settings-panel">
        <div className="settings-panel-title">
          <div className="metric-icon amber"><Search size={19} /></div>
          <div><strong>Quét repository local</strong><span>Tìm Git repository nhanh mà không làm nặng máy.</span></div>
        </div>
        <div className="settings-divider" />
        <div className="scan-depth-setting">
          <div><strong>Độ sâu khi quét</strong><span>Giới hạn số cấp thư mục để giữ ứng dụng phản hồi nhanh.</span></div>
          <select value={settings.scanDepth} onChange={(event) => onSave({ ...settings, scanDepth: Number(event.target.value) })}>
            {[2, 3, 4, 5, 6].map((depth) => <option key={depth} value={depth}>{depth} cấp</option>)}
          </select>
        </div>
      </div>

      <div className="settings-panel">
        <div className="settings-panel-title">
          <div className="metric-icon blue"><Github size={19} /></div>
          <div><strong>Kết nối GitHub</strong><span>Sử dụng tài khoản đã đăng nhập trong GitHub CLI.</span></div>
        </div>
        <div className="settings-divider" />
        <p className="settings-note">RepoFocus không lưu token riêng. Chạy <code>gh auth login</code> trong Terminal nếu phiên đăng nhập đã hết hạn.</p>
      </div>
    </section>
  );
}

function SlidersIcon() {
  return <CircleDot size={15} />;
}

function InspectorPlaceholder({
  icon,
  title,
  copy
}: {
  icon: React.ReactNode;
  title: string;
  copy: string;
}) {
  return (
    <div className="inspector-placeholder">
      {icon}
      <strong>{title}</strong>
      <span>{copy}</span>
    </div>
  );
}

function FieldRow({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="field-row">
      <span>{label}</span>
      <div>{children}</div>
    </div>
  );
}

function FocusControlSelect({
  value,
  onChange,
  options,
  searchable = false,
  ariaLabel
}: {
  value: string;
  onChange: (value: string) => void;
  options: Array<{ value: string; label: string; icon?: React.ReactNode }>;
  searchable?: boolean;
  ariaLabel: string;
}) {
  const [isOpen, setIsOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [opensUpward, setOpensUpward] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const selected = options.find((option) => option.value === value) ?? options[0];
  const normalizedQuery = query.trim().toLocaleLowerCase("vi");
  const filteredOptions = normalizedQuery
    ? options.filter((option) => option.label.toLocaleLowerCase("vi").includes(normalizedQuery))
    : options;

  useEffect(() => {
    if (!isOpen) return;
    const closeWhenLeaving = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) setIsOpen(false);
    };
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") setIsOpen(false);
    };
    document.addEventListener("pointerdown", closeWhenLeaving);
    document.addEventListener("keydown", closeOnEscape);
    return () => {
      document.removeEventListener("pointerdown", closeWhenLeaving);
      document.removeEventListener("keydown", closeOnEscape);
    };
  }, [isOpen]);

  return (
    <div
      ref={rootRef}
      className={`focus-control-select${isOpen ? " open" : ""}${opensUpward ? " opens-upward" : ""}`}
    >
      <button
        type="button"
        className="focus-control-trigger"
        aria-label={ariaLabel}
        aria-haspopup="listbox"
        aria-expanded={isOpen}
        onClick={() => {
          const willOpen = !isOpen;
          if (willOpen) {
            const bounds = rootRef.current?.getBoundingClientRect();
            const searchHeight = searchable && options.length > 8 ? 39 : 0;
            const menuHeight = Math.min(228, options.length * 31 + searchHeight + 10);
            const spaceBelow = bounds ? window.innerHeight - bounds.bottom : menuHeight;
            const spaceAbove = bounds?.top ?? 0;
            setOpensUpward(spaceBelow < menuHeight && spaceAbove > spaceBelow);
          }
          setQuery("");
          setIsOpen(willOpen);
        }}
      >
        {selected?.icon && <span className="focus-control-icon">{selected.icon}</span>}
        <span>{selected?.label ?? value}</span>
        <ChevronDown size={13} />
      </button>
      {isOpen && (
        <div className="focus-control-menu" role="listbox" aria-label={ariaLabel}>
          {searchable && options.length > 8 && (
            <label className="focus-control-search">
              <Search size={13} />
              <input autoFocus value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Tìm branch" />
            </label>
          )}
          <div className="focus-control-options">
            {filteredOptions.map((option) => (
              <button
                type="button"
                role="option"
                aria-selected={option.value === value}
                className={option.value === value ? "selected" : ""}
                key={option.value}
                onClick={() => {
                  onChange(option.value);
                  setIsOpen(false);
                }}
              >
                {option.icon && <span className="focus-control-icon">{option.icon}</span>}
                <span>{option.label}</span>
                {option.value === value && <Check size={13} />}
              </button>
            ))}
            {!filteredOptions.length && <span className="focus-control-empty">Không có kết quả.</span>}
          </div>
        </div>
      )}
    </div>
  );
}

function MetadataRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="metadata-row">
      <span>{label}</span>
      <strong title={value}>{value}</strong>
    </div>
  );
}

function RepoRow({
  repository,
  selected,
  showProgress,
  showDeadline = false,
  onSelect
}: {
  repository: Repository;
  selected: boolean;
  showProgress: boolean;
  showDeadline?: boolean;
  onSelect: () => void;
}) {
  const health = gitHealth(repository.tracking.gitStatus);
  const gitSignals = gitSignalCount(repository.tracking.gitStatus);
  const progress = displayedProgress(repository);
  const progressColor = progressTint(progress);
  const showsProgress = showProgress;
  const branch = repositoryBranch(repository);
  const isCompleted = repositoryIsCompleted(repository);
  const StatusIcon = statusIcon(repository.tracking.status);
  const ProviderIcon = providerIcon(repository.provider);
  return (
    <article
      className={`repo-row ${selected ? "selected" : ""} ${showsProgress ? "has-progress" : "no-progress"}`}
      onClick={onSelect}
      tabIndex={0}
      onKeyDown={(event) => {
        if (event.key === "Enter" || event.key === " ") onSelect();
      }}
    >
      <div className={`repo-icon status-${repository.tracking.status} ${repository.isPrivate ? "private" : ""}`}>
        {repository.isPrivate ? <Lock size={18} /> : <FolderGit2 size={19} />}
        {isCompleted && (
          <span className="completion-mark" title="Đã hoàn thành">
            <CheckCircle2 size={13} fill="currentColor" />
          </span>
        )}
      </div>
      <div className="repo-identity-column">
        <div className="repo-title-line">
          <strong>{repository.name}</strong>
          {repository.tracking.priority === "high" && <ArrowUpCircle className="priority-icon" size={13} aria-label="Ưu tiên cao" />}
        </div>
        <div className="repo-provider-line">
          <span className="repo-provider"><ProviderIcon size={12} /> {providerTitle(repository.provider)}</span>
          {branch ? (
            <span title={branch}><GitBranch size={12} /> {branch}</span>
          ) : (
            <span className="repo-language">{repository.primaryLanguage ?? "Chưa xác định branch"}</span>
          )}
        </div>
      </div>
      <div className="repo-work">
        <div className="repo-work-head">
          <span className={`status-pill status-${repository.tracking.status}`}>
            <StatusIcon size={12} />
            {STATUS_LABELS[repository.tracking.status]}
          </span>
          {repository.tracking.gitStatus && (
            <span className={`git-pill ${health.tone}`} title={health.label}>
              <CircleDot size={10} fill="currentColor" />
              {health.label}
              {gitSignals > 1 && <em>+{gitSignals - 1}</em>}
            </span>
          )}
          {repository.tracking.usesOutlinePlan && (
            <span className="checklist-pill"><CheckCircle2 size={11} /> {planCompletionSummary(repository).completed}/{planCompletionSummary(repository).total}</span>
          )}
        </div>
        <div className="repo-next-line">
          <ArrowRight size={12} />
          <span className={`next-action ${repository.tracking.nextAction ? "" : "empty"}`}>
            {repository.tracking.nextAction || "Chưa có việc tiếp theo"}
          </span>
          {showsProgress && (
            <div className="repo-progress" style={{ color: progressColor }}>
              <strong>{progress}%</strong>
              <span><i style={{ width: `${progress}%`, background: progressColor }} /></span>
            </div>
          )}
        </div>
      </div>
      <div className="repo-meta">
        <div>
          <span><CircleDot size={11} /> {repository.openIssueCount}</span>
          <span><GitPullRequest size={11} /> {repository.openPullRequestCount}</span>
        </div>
        {showDeadline && repository.tracking.deadline ? (
          <span title={`Hạn chót ${repository.tracking.deadline}`}>
            <Bell size={11} /> Quá hạn {repository.tracking.deadline}
          </span>
        ) : (
          <span>{lastPushLabel(repository)}</span>
        )}
      </div>
    </article>
  );
}

function displayedProgress(repository: Repository): number {
  if (repository.tracking.status === "done") return 100;
  if (repository.tracking.usesOutlinePlan) {
    const { completed, total } = planCompletionSummary(repository);
    return total ? Math.round((completed / total) * 100) : 0;
  }
  return repository.tracking.progress >= 100 ? 100 : repository.tracking.progress;
}

function progressTint(progress: number): string {
  if (progress >= 100) return "var(--progress-done)";
  if (progress >= 40) return "var(--progress-mid)";
  return "var(--progress-low)";
}

function GitStatusCard({ status }: { status: GitStatus | null }) {
  const health = gitHealth(status);
  if (!status) {
    return (
      <div className="git-status-card empty">
        <GitBranch size={19} />
        <span>Nhấn “Kiểm tra” để đọc trạng thái Git.</span>
      </div>
    );
  }
  return (
    <div className="git-status-card">
      <div className="git-branch-line">
        <span><GitBranch size={16} /> {status.branch || "Detached HEAD"}</span>
        <span>{status.hasUpstream ? "Có remote" : "Chưa có upstream"}</span>
      </div>
      <div className="git-metrics">
        <span className={health.tone}><CircleDot size={11} fill="currentColor" /> {health.label}</span>
        <span>↑ {status.aheadCount}</span>
        <span>↓ {status.behindCount}</span>
        <span>± {status.changedFileCount}</span>
      </div>
    </div>
  );
}

function CommitList({
  commits,
  pendingRevertSha,
  reverting,
  onRequestRevert,
  onCancelRevert,
  onConfirmRevert
}: {
  commits: CommitInfo[];
  pendingRevertSha: string | null;
  reverting: boolean;
  onRequestRevert: (sha: string) => void;
  onCancelRevert: () => void;
  onConfirmRevert: (sha: string) => void;
}) {
  if (!commits.length) return <p className="muted-copy">Chưa có commit.</p>;
  return (
    <div className="commit-list">
      {commits.map((commit) => (
        <div className="commit-item" key={commit.sha}>
          <div className="commit-item-main">
            <code>{commit.sha.slice(0, 7)}</code>
            <div>
              <strong>{commit.subject}</strong>
              <span>{commit.author} • {relativeDate(commit.committedAt)}</span>
            </div>
            {pendingRevertSha !== commit.sha && (
              <button className="commit-revert-button" onClick={() => onRequestRevert(commit.sha)} disabled={reverting}>
                <Undo2 size={13} /> Hoàn tác
              </button>
            )}
          </div>
          {pendingRevertSha === commit.sha && (
            <div className="commit-revert-confirmation">
              <p>Tạo commit mới để đảo ngược thay đổi “{commit.subject}”?</p>
              <div>
                <button className="secondary-button" onClick={onCancelRevert} disabled={reverting}>Hủy</button>
                <button className="commit-revert-confirm" onClick={() => onConfirmRevert(commit.sha)} disabled={reverting}>
                  {reverting ? <LoaderCircle className="spin" size={14} /> : <Undo2 size={14} />}
                  Tạo commit hoàn tác
                </button>
              </div>
            </div>
          )}
        </div>
      ))}
    </div>
  );
}

function Modal({
  title,
  onClose,
  children,
  className = "",
  dismissible = true
}: {
  title: string;
  onClose: () => void;
  children: React.ReactNode;
  className?: string;
  dismissible?: boolean;
}) {
  useEffect(() => {
    const close = (event: KeyboardEvent) => {
      if (dismissible && event.key === "Escape") onClose();
    };
    window.addEventListener("keydown", close);
    return () => window.removeEventListener("keydown", close);
  }, [dismissible, onClose]);
  return (
    <div className="modal-backdrop" onMouseDown={dismissible ? onClose : undefined}>
      <div className={`modal ${className}`} onMouseDown={(event) => event.stopPropagation()}>
        <div className="modal-header">
          <h2>{title}</h2>
          <button onClick={onClose} disabled={!dismissible}><X size={18} /></button>
        </div>
        {children}
      </div>
    </div>
  );
}

function LoadingList() {
  return (
    <div className="loading-list">
      {[0, 1, 2, 3, 4, 5].map((item) => (
        <div className="skeleton-row" key={item}>
          <span />
          <div><i /><i /></div>
        </div>
      ))}
    </div>
  );
}

function EmptyState({
  view,
  query,
}: {
  view: ViewKey;
  query: string;
}) {
  const content =
    view === "focus"
      ? {
          title: "Danh sách tập trung đang trống",
          message: "Mở Tất cả repo và chọn những việc quan trọng nhất lúc này.",
          icon: <Focus size={42} />
        }
      : view === "attention"
        ? {
            title: "Không có task quá hạn",
            message: "Không có task nào quá hạn mà vẫn chưa hoàn thành.",
            icon: <Box size={42} />
          }
        : view === "done"
          ? {
              title: "Chưa có repo hoàn thành",
              message: "Repo được đánh dấu Hoàn thành hoặc Đã lưu trữ sẽ xuất hiện tại đây.",
              icon: <Box size={42} />
            }
          : {
              title: "Không tìm thấy repo",
              message: query
                ? "Hãy thử một từ khóa khác."
                : "Hãy đồng bộ nguồn Git hoặc thêm repository trong phần Cài đặt.",
              icon: <Box size={42} />
            };

  return (
    <div className="empty-state mac-empty-state">
      <div className="empty-illustration">{content.icon}</div>
      <h2>{content.title}</h2>
      <p>{content.message}</p>
    </div>
  );
}

export default App;
