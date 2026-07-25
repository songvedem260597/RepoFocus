use crate::models::{
    CommitInfo, GitActionResult, GitConflictState, GitStatus, Repository, ScanResult, Tracking,
};
use chrono::{NaiveDate, TimeZone, Utc};
use std::{
    collections::{HashSet, VecDeque},
    ffi::OsStr,
    fs,
    path::{Path, PathBuf},
    process::{Command, Output},
};

fn command_output<I, S>(args: I) -> Result<Output, String>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    let mut command = Command::new("git");
    command
        .args(args)
        .env("LC_ALL", "C")
        .env("GIT_TERMINAL_PROMPT", "0")
        .env("GIT_SSH_COMMAND", "ssh -oBatchMode=yes")
        .creation_flags_no_window();
    command
        .output()
        .map_err(|error| format!("Không chạy được Git. Hãy kiểm tra Git for Windows: {error}"))
}

trait NoWindow {
    fn creation_flags_no_window(&mut self) -> &mut Self;
}

impl NoWindow for Command {
    fn creation_flags_no_window(&mut self) -> &mut Self {
        #[cfg(windows)]
        {
            use std::os::windows::process::CommandExt;
            self.creation_flags(0x08000000);
        }
        self
    }
}

fn output_text(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).trim().to_string()
}

fn output_error(output: &Output) -> String {
    let error = String::from_utf8_lossy(&output.stderr).trim().to_string();
    if error.is_empty() {
        output_text(output)
    } else {
        error
    }
}

pub fn git_status(path: &str) -> Result<GitStatus, String> {
    let path = validate_repo(path)?;
    let output = command_output([
        OsStr::new("-C"),
        path.as_os_str(),
        OsStr::new("status"),
        OsStr::new("--porcelain=v2"),
        OsStr::new("--branch"),
    ])?;

    if !output.status.success() {
        return Err(output_error(&output));
    }

    let mut status = GitStatus {
        checked_at: Some(Utc::now()),
        ..GitStatus::default()
    };

    for line in output_text(&output).lines() {
        if let Some(value) = line.strip_prefix("# branch.head ") {
            if value != "(detached)" {
                status.branch = Some(value.to_string());
            }
        } else if line.starts_with("# branch.upstream ") {
            status.has_upstream = true;
        } else if let Some(value) = line.strip_prefix("# branch.ab ") {
            for count in value.split_whitespace() {
                if let Some(ahead) = count.strip_prefix('+') {
                    status.ahead_count = ahead.parse().unwrap_or(0);
                } else if let Some(behind) = count.strip_prefix('-') {
                    status.behind_count = behind.parse().unwrap_or(0);
                }
            }
        } else if line.starts_with("u ") {
            status.changed_file_count += 1;
            status.conflict_count += 1;
        } else if line.starts_with("1 ") || line.starts_with("2 ") || line.starts_with("? ") {
            status.changed_file_count += 1;
        }
    }

    Ok(status)
}

pub fn recent_commits(path: &str, limit: u16) -> Result<Vec<CommitInfo>, String> {
    recent_commits_for_branch(path, None, limit)
}

#[derive(Debug)]
pub struct LocalRepositoryActivity {
    pub status: GitStatus,
    pub has_code_changes: bool,
}

pub fn local_activity_on_date(
    path: &str,
    date: NaiveDate,
) -> Result<LocalRepositoryActivity, String> {
    let status = git_status(path)?;
    let has_commit = has_commit_on_date(path, date)?;
    let has_code_changes = has_commit || status.changed_file_count > 0 || status.ahead_count > 0;
    Ok(LocalRepositoryActivity {
        status,
        has_code_changes,
    })
}

fn has_commit_on_date(path: &str, date: NaiveDate) -> Result<bool, String> {
    let path = validate_repo(path)?;
    let next_date = date
        .succ_opt()
        .ok_or_else(|| "Ngày kiểm tra Git không hợp lệ.".to_string())?;
    let since = format!("--since={date} 00:00:00");
    let until = format!("--until={next_date} 00:00:00");
    let output = command_output([
        OsStr::new("-C"),
        path.as_os_str(),
        OsStr::new("log"),
        OsStr::new("--branches"),
        OsStr::new("HEAD"),
        OsStr::new("-1"),
        OsStr::new("--format=%H"),
        OsStr::new(&since),
        OsStr::new(&until),
    ])?;
    if !output.status.success() {
        let error = output_error(&output);
        if error.contains("does not have any commits") {
            return Ok(false);
        }
        return Err(error);
    }
    Ok(!output_text(&output).is_empty())
}

/// Reads commits from a selected local branch so outline tasks stay tied to
/// the branch currently being focused, not merely the checked-out branch.
pub fn recent_commits_for_branch(
    path: &str,
    branch: Option<&str>,
    limit: u16,
) -> Result<Vec<CommitInfo>, String> {
    let path = validate_repo(path)?;
    let limit = limit.clamp(1, 200).to_string();
    let branch = branch.map(validate_branch).transpose()?;
    let mut arguments = vec![
        OsStr::new("-C"),
        path.as_os_str(),
        OsStr::new("log"),
        OsStr::new("-n"),
        OsStr::new(&limit),
        OsStr::new("--pretty=format:%H%x1f%ct%x1f%an%x1f%s"),
    ];
    if let Some(branch) = branch.as_deref() {
        arguments.push(OsStr::new(branch));
    }
    let output = command_output(arguments)?;

    if !output.status.success() {
        let error = output_error(&output);
        if error.contains("does not have any commits") {
            return Ok(Vec::new());
        }
        return Err(error);
    }

    Ok(output_text(&output)
        .lines()
        .filter_map(|line| {
            let fields: Vec<_> = line.split('\u{1f}').collect();
            let timestamp = fields.get(1)?.parse::<i64>().ok()?;
            Some(CommitInfo {
                sha: fields.first()?.to_string(),
                committed_at: Utc.timestamp_opt(timestamp, 0).single()?,
                author: fields.get(2)?.to_string(),
                subject: fields.get(3)?.to_string(),
            })
        })
        .collect())
}

/// Lists known local and origin-tracking branches for the Inspector without
/// contacting a remote. `origin/HEAD` is a symbolic pointer, not a branch a
/// user can select, so it is deliberately excluded.
pub fn local_branches(path: &str) -> Result<Vec<String>, String> {
    let path = validate_repo(path)?;
    let output = command_output([
        OsStr::new("-C"),
        path.as_os_str(),
        OsStr::new("for-each-ref"),
        OsStr::new("--format=%(refname:short)"),
        OsStr::new("refs/heads"),
        OsStr::new("refs/remotes/origin"),
    ])?;
    if !output.status.success() {
        return Err(output_error(&output));
    }

    let mut branches = output_text(&output)
        .lines()
        .map(str::trim)
        .filter(|branch| !branch.is_empty() && *branch != "origin/HEAD")
        .map(str::to_string)
        .collect::<Vec<_>>();
    branches.sort();
    branches.dedup();
    Ok(branches)
}

pub fn repository_from_path(path: &str) -> Result<Repository, String> {
    let canonical = validate_repo(path)?;
    let canonical_text = canonical.to_string_lossy().to_string();
    let origin = git_value(&canonical, &["config", "--get", "remote.origin.url"]);
    let branch = git_value(&canonical, &["branch", "--show-current"]);
    let full_name = origin
        .as_deref()
        .and_then(remote_full_name)
        .unwrap_or_else(|| {
            canonical
                .file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .to_string()
        });
    let name = full_name
        .rsplit('/')
        .next()
        .unwrap_or(&full_name)
        .trim_end_matches(".git")
        .to_string();
    let provider = origin
        .as_deref()
        .map(provider_from_url)
        .unwrap_or("local")
        .to_string();
    let id = origin
        .as_deref()
        .and_then(remote_full_name)
        .map(|remote| format!("{provider}:{remote}"))
        .unwrap_or_else(|| format!("local:{}", canonical_text.to_lowercase()));
    let status = git_status(&canonical_text)?;
    let local_branches = local_branches(&canonical_text)
        .ok()
        .filter(|branches| !branches.is_empty());

    Ok(Repository {
        id,
        name,
        full_name,
        description: None,
        url: origin.as_deref().and_then(remote_web_url),
        provider,
        is_private: false,
        is_archived: false,
        primary_language: None,
        default_branch: branch.filter(|value| !value.is_empty()),
        open_issue_count: 0,
        open_pull_request_count: 0,
        pushed_at: None,
        updated_at: Utc::now(),
        tracking: Tracking {
            local_path: Some(canonical_text),
            git_status: Some(status),
            local_branches,
            ..Tracking::default()
        },
    })
}

pub fn scan_repositories(root: &str, max_depth: u8) -> Result<ScanResult, String> {
    let root = PathBuf::from(root);
    if !root.is_dir() {
        return Err("Thư mục quét không tồn tại.".into());
    }

    let mut queue = VecDeque::from([(root, 0u8)]);
    let mut repositories = Vec::new();
    let mut visited_folders = 0u32;
    let mut skipped_folders = 0u32;

    while let Some((folder, depth)) = queue.pop_front() {
        visited_folders += 1;
        if folder.join(".git").exists() {
            if let Ok(repository) = repository_from_path(&folder.to_string_lossy()) {
                repositories.push(repository);
            }
            continue;
        }
        if depth >= max_depth {
            skipped_folders += 1;
            continue;
        }

        let entries = match fs::read_dir(&folder) {
            Ok(entries) => entries,
            Err(_) => {
                skipped_folders += 1;
                continue;
            }
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() && !should_skip(&path) {
                queue.push_back((path, depth + 1));
            }
        }
    }

    repositories.sort_by(|left, right| {
        left.full_name
            .to_lowercase()
            .cmp(&right.full_name.to_lowercase())
    });
    Ok(ScanResult {
        repositories,
        visited_folders,
        skipped_folders,
    })
}

/// Searches the conventional per-user source folders for a checkout matching a
/// tracked repository. The scan is read-only, bounded, and compares origin
/// remotes before falling back to an unambiguous folder-name match.
pub fn locate_repository_checkout(repository: &Repository) -> Result<Option<String>, String> {
    let roots = default_locator_roots();
    locate_repository_in_roots(repository, &roots, 7)
        .map(|path| path.map(|value| value.to_string_lossy().to_string()))
}

fn locate_repository_in_roots(
    repository: &Repository,
    roots: &[PathBuf],
    maximum_depth: u8,
) -> Result<Option<PathBuf>, String> {
    let target_name = repository.name.trim().to_lowercase();
    let target_full_name = repository.full_name.trim().to_lowercase();
    let target_provider = repository.provider.trim().to_lowercase();
    let mut name_candidates = Vec::new();

    for checkout in discover_git_repository_paths(roots, maximum_depth) {
        if let Some(remote) = git_value(&checkout, &["config", "--get", "remote.origin.url"]) {
            let matches_remote = remote_full_name(&remote)
                .is_some_and(|full_name| full_name.eq_ignore_ascii_case(&target_full_name));
            let remote_provider = provider_from_url(&remote);
            let matches_provider = target_provider.is_empty()
                || matches!(target_provider.as_str(), "local" | "other")
                || remote_provider.eq_ignore_ascii_case(&target_provider);
            if matches_remote && matches_provider {
                return Ok(Some(checkout));
            }
        }

        if !target_name.is_empty()
            && checkout
                .file_name()
                .is_some_and(|name| name.to_string_lossy().eq_ignore_ascii_case(&target_name))
        {
            name_candidates.push(checkout);
        }
    }

    if name_candidates.len() == 1 {
        return Ok(name_candidates.pop());
    }
    Ok(None)
}

fn default_locator_roots() -> Vec<PathBuf> {
    let Some(home) = std::env::var_os("USERPROFILE").map(PathBuf::from) else {
        return Vec::new();
    };
    ["Developer", "Projects", "Code", "GitHub"]
        .into_iter()
        .map(|name| home.join(name))
        .filter(|path| path.is_dir())
        .collect()
}

fn discover_git_repository_paths(roots: &[PathBuf], maximum_depth: u8) -> Vec<PathBuf> {
    let mut queue = roots
        .iter()
        .filter(|path| path.is_dir())
        .cloned()
        .map(|path| (path, 0u8))
        .collect::<VecDeque<_>>();
    let mut visited = HashSet::new();
    let mut repositories = Vec::new();

    while let Some((folder, depth)) = queue.pop_front() {
        let normalized = folder.canonicalize().unwrap_or(folder.clone());
        if !visited.insert(normalized) {
            continue;
        }
        if folder.join(".git").exists() {
            if let Ok(root) = validate_repo(&folder.to_string_lossy()) {
                repositories.push(root);
            }
            continue;
        }
        if depth >= maximum_depth {
            continue;
        }

        let Ok(entries) = fs::read_dir(&folder) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() && !should_skip(&path) {
                queue.push_back((path, depth + 1));
            }
        }
    }

    repositories.sort();
    repositories.dedup();
    repositories
}

pub fn clone_repository(url: &str, parent: &str) -> Result<Repository, String> {
    let url = url.trim();
    if url.is_empty() {
        return Err("Hãy nhập URL repository.".into());
    }
    let parent = PathBuf::from(parent);
    if !parent.is_dir() {
        return Err("Thư mục đích không tồn tại.".into());
    }

    let name = url
        .trim_end_matches('/')
        .rsplit(['/', ':'])
        .next()
        .unwrap_or("repository")
        .trim_end_matches(".git");
    if name.is_empty() {
        return Err("URL repository không hợp lệ.".into());
    }
    let target = parent.join(name);
    if target.exists() {
        return Err(format!("Thư mục đích đã tồn tại: {}", target.display()));
    }

    let output = command_output([
        OsStr::new("clone"),
        OsStr::new("--progress"),
        OsStr::new(url),
        target.as_os_str(),
    ])?;
    if !output.status.success() {
        return Err(output_error(&output));
    }
    repository_from_path(&target.to_string_lossy())
}

pub fn run_action(path: &str, action: &str) -> Result<GitActionResult, String> {
    let path = validate_repo(path)?;
    let (output, fallback) = match action {
        "fetch" => (
            require_success(repo_command(&path, &["fetch", "--prune"])?)?,
            "Đã tải thông tin mới từ remote.",
        ),
        "pull" => (
            require_success(repo_command(&path, &["pull", "--ff-only"])?)?,
            "Repository đã được cập nhật.",
        ),
        "push" => (push_with_upstream(&path)?, "Đã đẩy commit lên remote."),
        _ => return Err("Thao tác Git không được hỗ trợ.".into()),
    };
    action_result(&path, output, fallback)
}

/// Changes the checkout without ever invoking a shell. The branch name is
/// validated by Git and is always passed after `--`.
pub fn switch_branch(path: &str, branch: &str) -> Result<GitActionResult, String> {
    let path = validate_repo(path)?;
    let branch = validate_branch(branch)?;
    let output = if branch.starts_with("origin/") {
        require_success(repo_command(&path, &["switch", "--track", &branch])?)?
    } else {
        require_success(repo_command(&path, &["switch", "--", &branch])?)?
    };
    action_result(&path, output, &format!("Đã chuyển sang branch {branch}."))
}

/// Stages all working-tree changes and creates a commit, matching the macOS
/// workspace behavior. It deliberately rejects an empty commit instead of
/// asking Git to open an editor.
pub fn commit_all(path: &str, message: &str) -> Result<GitActionResult, String> {
    let path = validate_repo(path)?;
    let message = message.trim();
    if message.is_empty() {
        return Err("Hãy nhập nội dung commit.".into());
    }

    require_success(repo_command(&path, &["add", "-A"])?)?;
    let staged = repo_command(&path, &["diff", "--cached", "--quiet"])?;
    match staged.status.code() {
        Some(0) => return Err("Không có thay đổi để commit.".into()),
        Some(1) => {}
        _ => return Err(output_error(&staged)),
    }

    let output = require_success(repo_command(&path, &["commit", "-m", message])?)?;
    action_result(&path, output, "Đã tạo commit mới.")
}

/// Merges a selected local branch into the current branch. Git leaves a
/// conflict in place when necessary so the user can resolve it safely.
pub fn merge_branch(path: &str, branch: &str) -> Result<GitActionResult, String> {
    let path = validate_repo(path)?;
    let branch = validate_branch(branch)?;
    let output = require_success(repo_command(&path, &["merge", "--no-edit", "--", &branch])?)?;
    action_result(&path, output, &format!("Đã merge branch {branch}."))
}

/// Reverts through a new commit; no history-rewriting command is exposed by
/// the Windows client.
pub fn revert_commit(path: &str, sha: &str) -> Result<GitActionResult, String> {
    let path = validate_repo(path)?;
    let sha = validate_commit_sha(sha)?;
    let output = require_success(repo_command(&path, &["revert", "--no-edit", "--", &sha])?)?;
    action_result(
        &path,
        output,
        &format!("Đã tạo commit hoàn tác {}.", &sha[..7]),
    )
}

/// Returns the unresolved files and any merge/revert sequence in progress.
/// The state is deliberately ephemeral: Git remains the source of truth.
pub fn conflict_state(path: &str) -> Result<GitConflictState, String> {
    let path = validate_repo(path)?;
    Ok(GitConflictState {
        files: conflicted_files_for_path(&path)?,
        sequence: sequence_state_for_path(&path)?,
    })
}

/// Marks one conflicted file as resolved. The choice must be one of the
/// options the UI presents and the target must still appear in Git's conflict
/// list, preventing arbitrary path staging.
pub fn resolve_conflict(path: &str, file: &str, choice: &str) -> Result<GitActionResult, String> {
    let path = validate_repo(path)?;
    let file = file.trim();
    if file.is_empty()
        || !conflicted_files_for_path(&path)?
            .iter()
            .any(|item| item == file)
    {
        return Err("File này không còn nằm trong danh sách conflict.".into());
    }

    match choice {
        "ours" => {
            require_success(repo_command(&path, &["checkout", "--ours", "--", file])?)?;
        }
        "theirs" => {
            require_success(repo_command(&path, &["checkout", "--theirs", "--", file])?)?;
        }
        "markResolved" => {}
        _ => return Err("Cách xử lý conflict không hợp lệ.".into()),
    }
    let output = require_success(repo_command(&path, &["add", "--", file])?)?;
    action_result(&path, output, &format!("Đã đánh dấu {file} là đã xử lý."))
}

pub fn continue_conflict_operation(path: &str) -> Result<GitActionResult, String> {
    let path = validate_repo(path)?;
    if !conflicted_files_for_path(&path)?.is_empty() {
        return Err("Hãy xử lý hết file conflict trước khi tiếp tục.".into());
    }
    let output = match sequence_state_for_path(&path)?.as_str() {
        "merge" => require_success(repo_command(&path, &["commit", "--no-edit"])?)?,
        "revert" => require_success(repo_command(&path, &["revert", "--continue"])?)?,
        _ => return Err("Không có merge hoặc revert nào đang chờ xử lý.".into()),
    };
    action_result(&path, output, "Đã hoàn tất thao tác Git.")
}

/// Abort is only exposed after an explicit confirmation in the UI. It never
/// touches commits that existed before the in-progress merge or revert.
pub fn abort_conflict_operation(path: &str) -> Result<GitActionResult, String> {
    let path = validate_repo(path)?;
    let output = match sequence_state_for_path(&path)?.as_str() {
        "merge" => require_success(repo_command(&path, &["merge", "--abort"])?)?,
        "revert" => require_success(repo_command(&path, &["revert", "--abort"])?)?,
        _ => return Err("Không có merge hoặc revert nào đang chờ xử lý.".into()),
    };
    action_result(&path, output, "Đã hủy thao tác Git đang chờ.")
}

fn conflicted_files_for_path(path: &Path) -> Result<Vec<String>, String> {
    let output = require_success(repo_command(
        path,
        &["diff", "--name-only", "--diff-filter=U", "-z"],
    )?)?;
    let mut files = String::from_utf8_lossy(&output.stdout)
        .split('\0')
        .map(str::trim)
        .filter(|file| !file.is_empty())
        .map(str::to_string)
        .collect::<Vec<_>>();
    files.sort();
    files.dedup();
    Ok(files)
}

fn sequence_state_for_path(path: &Path) -> Result<String, String> {
    let directory = require_success(repo_command(path, &["rev-parse", "--absolute-git-dir"])?)?;
    let git_directory = PathBuf::from(output_text(&directory));
    if git_directory.join("MERGE_HEAD").is_file() {
        return Ok("merge".into());
    }
    if git_directory.join("REVERT_HEAD").is_file() {
        return Ok("revert".into());
    }
    let sequencer = git_directory.join("sequencer").join("todo");
    if let Ok(contents) = fs::read_to_string(sequencer) {
        if contents.lines().any(|line| line.starts_with("revert ")) {
            return Ok("revert".into());
        }
    }
    Ok("none".into())
}

fn repo_command(path: &Path, args: &[&str]) -> Result<Output, String> {
    let mut command_args = vec![OsStr::new("-C"), path.as_os_str()];
    command_args.extend(args.iter().copied().map(OsStr::new));
    command_output(command_args)
}

fn require_success(output: Output) -> Result<Output, String> {
    if output.status.success() {
        Ok(output)
    } else {
        Err(output_error(&output))
    }
}

fn action_result(path: &Path, output: Output, fallback: &str) -> Result<GitActionResult, String> {
    let message = output_text(&output);
    Ok(GitActionResult {
        message: if message.is_empty() {
            fallback.to_string()
        } else {
            message
        },
        status: git_status(&path.to_string_lossy())?,
    })
}

fn push_with_upstream(path: &Path) -> Result<Output, String> {
    let upstream = repo_command(path, &["rev-parse", "--abbrev-ref", "@{upstream}"])?;
    if upstream.status.success() {
        return require_success(repo_command(path, &["push"])?);
    }

    let origin = repo_command(path, &["remote", "get-url", "origin"])?;
    if !origin.status.success() {
        return Err("Chưa có remote origin để push.".into());
    }
    let branch = require_success(repo_command(path, &["branch", "--show-current"])?)?;
    let branch = output_text(&branch);
    if branch.is_empty() {
        return Err("Không thể push khi repository đang ở Detached HEAD.".into());
    }
    require_success(repo_command(
        path,
        &["push", "--set-upstream", "origin", &branch],
    )?)
}

fn validate_branch(branch: &str) -> Result<String, String> {
    let branch = branch.trim();
    if branch.is_empty() {
        return Err("Hãy chọn một branch.".into());
    }
    let output = command_output([
        OsStr::new("check-ref-format"),
        OsStr::new("--branch"),
        OsStr::new(branch),
    ])?;
    if !output.status.success() {
        return Err("Tên branch không hợp lệ.".into());
    }
    Ok(branch.to_string())
}

fn validate_commit_sha(sha: &str) -> Result<String, String> {
    let sha = sha.trim();
    if !(7..=40).contains(&sha.len()) || !sha.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err("Mã commit không hợp lệ.".into());
    }
    Ok(sha.to_string())
}

fn validate_repo(path: &str) -> Result<PathBuf, String> {
    let path = PathBuf::from(path.trim());
    if !path.is_dir() {
        return Err("Không tìm thấy thư mục repository.".into());
    }
    let output = command_output([
        OsStr::new("-C"),
        path.as_os_str(),
        OsStr::new("rev-parse"),
        OsStr::new("--show-toplevel"),
    ])?;
    if !output.status.success() {
        return Err("Thư mục này không phải Git repository.".into());
    }
    let root = PathBuf::from(output_text(&output));
    root.canonicalize()
        .map_err(|error| format!("Không thể đọc đường dẫn repository: {error}"))
}

fn git_value(path: &Path, args: &[&str]) -> Option<String> {
    let mut command_args = vec![OsStr::new("-C"), path.as_os_str()];
    command_args.extend(args.iter().map(OsStr::new));
    command_output(command_args)
        .ok()
        .filter(|output| output.status.success())
        .map(|output| output_text(&output))
        .filter(|value| !value.is_empty())
}

fn provider_from_url(url: &str) -> &'static str {
    let lower = url.to_lowercase();
    if lower.contains("github.com") {
        "github"
    } else if lower.contains("gitlab.com") {
        "gitlab"
    } else {
        "other"
    }
}

fn remote_full_name(url: &str) -> Option<String> {
    let normalized = url
        .trim()
        .trim_end_matches('/')
        .trim_end_matches(".git")
        .replace('\\', "/");
    let path = if let Some((_, path)) = normalized.split_once("://") {
        path.split_once('/').map(|(_, rest)| rest.to_string())
    } else if let Some((_, path)) = normalized.split_once(':') {
        Some(path.to_string())
    } else {
        None
    }?;
    let path = path.trim_matches('/').to_string();
    if path.contains('/') {
        Some(path)
    } else {
        None
    }
}

fn remote_web_url(url: &str) -> Option<String> {
    let full_name = remote_full_name(url)?;
    match provider_from_url(url) {
        "github" => Some(format!("https://github.com/{full_name}")),
        "gitlab" => Some(format!("https://gitlab.com/{full_name}")),
        _ if url.starts_with("http://") || url.starts_with("https://") => {
            Some(url.trim_end_matches(".git").to_string())
        }
        _ => None,
    }
}

fn should_skip(path: &Path) -> bool {
    let name = path
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .to_lowercase();
    name.starts_with('.')
        || matches!(
            name.as_str(),
            "node_modules"
                | "target"
                | "build"
                | "dist"
                | "vendor"
                | "packages"
                | "$recycle.bin"
                | "windows"
                | "program files"
                | "program files (x86)"
        )
}

#[cfg(test)]
mod tests {
    use super::{
        commit_all, conflict_state, continue_conflict_operation, has_commit_on_date,
        local_activity_on_date, local_branches, merge_branch, recent_commits_for_branch,
        resolve_conflict, revert_commit, run_action, switch_branch,
    };
    use chrono::Local;
    use std::{
        fs,
        path::{Path, PathBuf},
        process::Command,
        time::{SystemTime, UNIX_EPOCH},
    };

    struct TemporaryRepository(PathBuf);

    impl TemporaryRepository {
        fn create() -> Self {
            let nonce = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("system time should be after Unix epoch")
                .as_nanos();
            let root = std::env::temp_dir().join(format!(
                "repofocus-git-workspace-test-{}-{nonce}",
                std::process::id()
            ));
            let repository = root.join("repository");
            fs::create_dir_all(&repository)
                .expect("temporary repository directory should be created");
            run_git(&repository, &["init"]);
            run_git(&repository, &["config", "user.name", "RepoFocus test"]);
            run_git(
                &repository,
                &["config", "user.email", "repofocus-test@example.invalid"],
            );
            run_git(&repository, &["checkout", "-b", "main"]);
            fs::write(repository.join("README.md"), "initial\n")
                .expect("initial file should be written");
            run_git(&repository, &["add", "README.md"]);
            run_git(&repository, &["commit", "-m", "initial commit"]);
            Self(root)
        }

        fn repository(&self) -> PathBuf {
            self.0.join("repository")
        }
    }

    impl Drop for TemporaryRepository {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn run_git(path: &Path, args: &[&str]) {
        let output = Command::new("git")
            .arg("-C")
            .arg(path)
            .args(args)
            .output()
            .expect("Git should run in this test environment");
        assert!(
            output.status.success(),
            "git {} failed: {}",
            args.join(" "),
            String::from_utf8_lossy(&output.stderr)
        );
    }

    fn git_stdout(path: &Path, args: &[&str]) -> String {
        let output = Command::new("git")
            .arg("-C")
            .arg(path)
            .args(args)
            .output()
            .expect("Git should run in this test environment");
        assert!(output.status.success());
        String::from_utf8_lossy(&output.stdout).trim().to_string()
    }

    #[test]
    fn workspace_commands_use_safe_git_operations() {
        let temporary = TemporaryRepository::create();
        let repository = temporary.repository();
        let repository_text = repository.to_string_lossy().to_string();

        run_git(&repository, &["switch", "-c", "feature/workspace"]);
        fs::write(repository.join("feature.txt"), "feature\n")
            .expect("feature file should be written");
        commit_all(&repository_text, "add feature work")
            .expect("commit all should stage and commit");
        assert!(
            recent_commits_for_branch(&repository_text, Some("feature/workspace"), 10)
                .expect("branch history should be listed")
                .iter()
                .any(|commit| commit.subject == "add feature work")
        );

        switch_branch(&repository_text, "main").expect("switch branch should work");
        assert_eq!(
            git_stdout(&repository, &["branch", "--show-current"]),
            "main"
        );
        merge_branch(&repository_text, "feature/workspace").expect("merge should work");
        assert!(repository.join("feature.txt").exists());

        fs::write(repository.join("revert-me.txt"), "temporary\n")
            .expect("test file should be written");
        commit_all(&repository_text, "add temporary file").expect("second commit should work");
        let sha = git_stdout(&repository, &["rev-parse", "HEAD"]);
        revert_commit(&repository_text, &sha).expect("revert should create a new commit");
        assert!(!repository.join("revert-me.txt").exists());

        let remote = temporary.0.join("remote.git");
        let output = Command::new("git")
            .args(["init", "--bare"])
            .arg(&remote)
            .output()
            .expect("bare remote should be created");
        assert!(output.status.success());
        let remote_text = remote.to_string_lossy().to_string();
        run_git(&repository, &["remote", "add", "origin", &remote_text]);
        run_action(&repository_text, "push").expect("push should configure the first upstream");
        assert_eq!(
            git_stdout(&repository, &["rev-parse", "--abbrev-ref", "@{upstream}"]),
            "origin/main"
        );
        let branches = local_branches(&repository_text).expect("known branches should be listed");
        assert!(branches.contains(&"main".to_string()));
        assert!(branches.contains(&"origin/main".to_string()));

        fs::write(repository.join("conflict.txt"), "base\n")
            .expect("conflict base file should be written");
        commit_all(&repository_text, "add conflict base").expect("base commit should work");
        run_git(&repository, &["switch", "-c", "conflict/feature"]);
        fs::write(repository.join("conflict.txt"), "feature\n")
            .expect("feature conflict file should be written");
        commit_all(&repository_text, "change conflict on feature")
            .expect("feature conflict commit should work");
        switch_branch(&repository_text, "main").expect("switch back to main should work");
        fs::write(repository.join("conflict.txt"), "main\n")
            .expect("main conflict file should be written");
        commit_all(&repository_text, "change conflict on main")
            .expect("main conflict commit should work");

        assert!(merge_branch(&repository_text, "conflict/feature").is_err());
        let conflict = conflict_state(&repository_text).expect("conflict state should be readable");
        assert_eq!(conflict.files, vec!["conflict.txt"]);
        assert_eq!(conflict.sequence, "merge");
        resolve_conflict(&repository_text, "conflict.txt", "theirs")
            .expect("theirs choice should stage the resolved file");
        assert!(conflict_state(&repository_text)
            .expect("updated conflict state should be readable")
            .files
            .is_empty());
        continue_conflict_operation(&repository_text)
            .expect("merge should continue after resolution");
        assert_eq!(
            fs::read_to_string(repository.join("conflict.txt"))
                .expect("resolved file should be readable")
                .trim(),
            "feature"
        );
        assert_eq!(
            conflict_state(&repository_text)
                .expect("final conflict state should be readable")
                .sequence,
            "none"
        );
    }

    #[test]
    fn local_activity_detects_today_commits_and_dirty_worktrees() {
        let temporary = TemporaryRepository::create();
        let repository = temporary.repository();
        let repository_text = repository.to_string_lossy().to_string();
        let today = Local::now().date_naive();
        let previous_day = today
            .pred_opt()
            .expect("the current date should have a previous day");

        assert!(has_commit_on_date(&repository_text, today)
            .expect("today's commit activity should be checked"));
        assert!(!has_commit_on_date(&repository_text, previous_day)
            .expect("the previous day should be checked"));

        fs::write(repository.join("dirty.txt"), "work in progress\n")
            .expect("dirty worktree file should be written");
        let activity = local_activity_on_date(&repository_text, previous_day)
            .expect("local activity should be readable");
        assert!(activity.has_code_changes);
        assert_eq!(activity.status.changed_file_count, 1);
    }
}
