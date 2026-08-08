mod git;
mod github;
mod gitlab;
mod models;
mod storage;

use chrono::{NaiveDate, Utc};
use models::{
    AppData, AutoFocusResult, CommitInfo, ContributionDay, GitActionResult, GitConflictState,
    GitStatus, RemoteActivity, Repository, ScanResult, Settings,
};
use std::collections::HashMap;
use storage::AppStore;
use tauri::{Emitter, Manager, State, WebviewWindow};

#[tauri::command]
fn load_data(store: State<'_, AppStore>) -> Result<AppData, String> {
    store.snapshot()
}

#[tauri::command]
fn save_repository(
    store: State<'_, AppStore>,
    mut repository: Repository,
) -> Result<AppData, String> {
    repository.normalize_tracking();
    repository.tracking.modified_at = Utc::now();
    store.upsert(repository)
}

#[tauri::command]
fn remove_repository(store: State<'_, AppStore>, repository_id: String) -> Result<AppData, String> {
    store.remove(&repository_id)
}

#[tauri::command]
fn save_settings(store: State<'_, AppStore>, settings: Settings) -> Result<AppData, String> {
    store.update_settings(settings)
}

#[tauri::command]
async fn import_repository(store: State<'_, AppStore>, path: String) -> Result<AppData, String> {
    let repository = tauri::async_runtime::spawn_blocking(move || git::repository_from_path(&path))
        .await
        .map_err(|error| error.to_string())??;
    store.upsert(merge_with_existing(&store.snapshot()?, repository))
}

#[tauri::command]
async fn scan_repositories(
    store: State<'_, AppStore>,
    root: String,
    max_depth: u8,
) -> Result<ScanResult, String> {
    let result =
        tauri::async_runtime::spawn_blocking(move || git::scan_repositories(&root, max_depth))
            .await
            .map_err(|error| error.to_string())??;
    let current = store.snapshot()?;
    for repository in &result.repositories {
        store.upsert(merge_with_existing(&current, repository.clone()))?;
    }
    Ok(result)
}

#[tauri::command]
async fn auto_detect_local_repository(
    store: State<'_, AppStore>,
    repository_id: String,
) -> Result<AppData, String> {
    let repository = store
        .snapshot()?
        .repositories
        .into_iter()
        .find(|item| item.id == repository_id)
        .ok_or_else(|| "KhÃ´ng tÃ¬m tháº¥y repository cáº§n kiá»ƒm tra.".to_string())?;
    let detected_path =
        tauri::async_runtime::spawn_blocking(move || git::locate_repository_checkout(&repository))
            .await
            .map_err(|error| error.to_string())??;

    let Some(path) = detected_path else {
        return store.snapshot();
    };
    let checked_path = path.clone();
    let (status, local_branches) = tauri::async_runtime::spawn_blocking(move || {
        let status = git::git_status(&checked_path)?;
        let local_branches = git::local_branches(&checked_path).ok();
        Ok::<_, String>((status, local_branches))
    })
    .await
    .map_err(|error| error.to_string())??;

    let mut data = store.snapshot()?;
    let target = data
        .repositories
        .iter_mut()
        .find(|item| item.id == repository_id)
        .ok_or_else(|| {
            "Repository Ä‘Ã£ thay Ä‘á»•i trong khi Ä‘ang tÃ¬m trÃªn mÃ¡y.".to_string()
        })?;
    target.tracking.local_path = Some(path);
    target.tracking.git_status = Some(status);
    target.tracking.local_branches = local_branches;
    target.tracking.modified_at = Utc::now();
    store.replace(data)?;
    store.snapshot()
}

#[tauri::command]
async fn bootstrap_local_repositories(store: State<'_, AppStore>) -> Result<AppData, String> {
    let repositories = store.snapshot()?.repositories;
    let states = tauri::async_runtime::spawn_blocking(move || {
        git::refresh_local_repositories(&repositories)
    })
    .await
    .map_err(|error| error.to_string())?;

    let mut data = store.snapshot()?;
    for state in states {
        let Some(repository) = data
            .repositories
            .iter_mut()
            .find(|repository| repository.id == state.repository_id)
        else {
            continue;
        };
        repository.tracking.local_path = Some(state.path);
        repository.tracking.git_status = Some(state.status);
        repository.tracking.local_branches = state.local_branches;
    }
    store.replace(data.clone())?;
    Ok(data)
}

#[tauri::command]
async fn refresh_git(path: String) -> Result<GitStatus, String> {
    tauri::async_runtime::spawn_blocking(move || git::git_status(&path))
        .await
        .map_err(|error| error.to_string())?
}

#[tauri::command]
async fn list_commits(path: String, limit: u16) -> Result<Vec<CommitInfo>, String> {
    tauri::async_runtime::spawn_blocking(move || git::recent_commits(&path, limit))
        .await
        .map_err(|error| error.to_string())?
}

#[tauri::command]
async fn list_commits_for_branch(
    path: String,
    branch: String,
    limit: u16,
) -> Result<Vec<CommitInfo>, String> {
    tauri::async_runtime::spawn_blocking(move || {
        git::recent_commits_for_branch(&path, Some(&branch), limit)
    })
    .await
    .map_err(|error| error.to_string())?
}

#[tauri::command]
async fn list_local_branches(path: String) -> Result<Vec<String>, String> {
    tauri::async_runtime::spawn_blocking(move || git::local_branches(&path))
        .await
        .map_err(|error| error.to_string())?
}

#[tauri::command]
async fn git_action(path: String, action: String) -> Result<GitActionResult, String> {
    tauri::async_runtime::spawn_blocking(move || git::run_action(&path, &action))
        .await
        .map_err(|error| error.to_string())?
}

#[tauri::command]
async fn switch_git_branch(path: String, branch: String) -> Result<GitActionResult, String> {
    tauri::async_runtime::spawn_blocking(move || git::switch_branch(&path, &branch))
        .await
        .map_err(|error| error.to_string())?
}

#[tauri::command]
async fn commit_all_git_changes(path: String, message: String) -> Result<GitActionResult, String> {
    tauri::async_runtime::spawn_blocking(move || git::commit_all(&path, &message))
        .await
        .map_err(|error| error.to_string())?
}

#[tauri::command]
async fn merge_git_branch(path: String, branch: String) -> Result<GitActionResult, String> {
    tauri::async_runtime::spawn_blocking(move || git::merge_branch(&path, &branch))
        .await
        .map_err(|error| error.to_string())?
}

#[tauri::command]
async fn revert_git_commit(path: String, sha: String) -> Result<GitActionResult, String> {
    tauri::async_runtime::spawn_blocking(move || git::revert_commit(&path, &sha))
        .await
        .map_err(|error| error.to_string())?
}

#[tauri::command]
async fn git_conflict_state(path: String) -> Result<GitConflictState, String> {
    tauri::async_runtime::spawn_blocking(move || git::conflict_state(&path))
        .await
        .map_err(|error| error.to_string())?
}

#[tauri::command]
async fn resolve_git_conflict(
    path: String,
    file: String,
    choice: String,
) -> Result<GitActionResult, String> {
    tauri::async_runtime::spawn_blocking(move || git::resolve_conflict(&path, &file, &choice))
        .await
        .map_err(|error| error.to_string())?
}

#[tauri::command]
async fn continue_git_conflict_operation(path: String) -> Result<GitActionResult, String> {
    tauri::async_runtime::spawn_blocking(move || git::continue_conflict_operation(&path))
        .await
        .map_err(|error| error.to_string())?
}

#[tauri::command]
async fn abort_git_conflict_operation(path: String) -> Result<GitActionResult, String> {
    tauri::async_runtime::spawn_blocking(move || git::abort_conflict_operation(&path))
        .await
        .map_err(|error| error.to_string())?
}

#[tauri::command]
async fn clone_repository(
    window: WebviewWindow,
    store: State<'_, AppStore>,
    url: String,
    parent: String,
) -> Result<AppData, String> {
    let progress_window = window.clone();
    let repository = tauri::async_runtime::spawn_blocking(move || {
        git::clone_repository_with_progress(&url, &parent, |progress| {
            let _ = progress_window.emit("clone-progress", progress);
        })
    })
    .await
    .map_err(|error| error.to_string())??;
    store.upsert(merge_with_existing(&store.snapshot()?, repository))
}

#[tauri::command]
async fn sync_github(store: State<'_, AppStore>) -> Result<AppData, String> {
    let remote_repositories = tauri::async_runtime::spawn_blocking(github::list_repositories)
        .await
        .map_err(|error| error.to_string())??;
    let mut data = store.snapshot()?;

    for mut remote in remote_repositories {
        if remote.is_archived {
            remote.tracking.status = "archived".into();
        }
        if let Some(existing) = data.repositories.iter_mut().find(|item| {
            item.id.eq_ignore_ascii_case(&remote.id)
                || item.full_name.eq_ignore_ascii_case(&remote.full_name)
        }) {
            let tracking = existing.tracking.clone();
            *existing = remote;
            existing.tracking = tracking;
        } else {
            data.repositories.push(remote);
        }
    }
    data.last_sync_at = Some(Utc::now());
    store.replace(data.clone())?;
    Ok(data)
}

#[tauri::command]
async fn sync_gitlab(store: State<'_, AppStore>) -> Result<AppData, String> {
    let remote_repositories = tauri::async_runtime::spawn_blocking(gitlab::list_repositories)
        .await
        .map_err(|error| error.to_string())??;
    let mut data = store.snapshot()?;

    for mut remote in remote_repositories {
        if remote.is_archived {
            remote.tracking.status = "archived".into();
        }
        if let Some(existing) = data.repositories.iter_mut().find(|item| {
            item.id.eq_ignore_ascii_case(&remote.id)
                || item.full_name.eq_ignore_ascii_case(&remote.full_name)
        }) {
            let tracking = existing.tracking.clone();
            *existing = remote;
            existing.tracking = tracking;
        } else {
            data.repositories.push(remote);
        }
    }
    data.last_sync_at = Some(Utc::now());
    store.replace(data.clone())?;
    Ok(data)
}

#[tauri::command]
async fn github_activity(date: String) -> Result<Vec<RemoteActivity>, String> {
    tauri::async_runtime::spawn_blocking(move || github::activity_for_date(&date))
        .await
        .map_err(|error| error.to_string())?
}

#[tauri::command]
async fn gitlab_activity(date: String) -> Result<Vec<RemoteActivity>, String> {
    tauri::async_runtime::spawn_blocking(move || gitlab::activity_for_date(&date))
        .await
        .map_err(|error| error.to_string())?
}

#[tauri::command]
async fn contribution_calendar(days: u32) -> Result<Vec<ContributionDay>, String> {
    let github_task =
        tauri::async_runtime::spawn_blocking(move || github::contribution_calendar(days));
    let gitlab_task =
        tauri::async_runtime::spawn_blocking(move || gitlab::contribution_calendar(days));
    let mut counts = HashMap::<String, u32>::new();
    let mut succeeded = false;
    if let Ok(Ok(items)) = github_task.await {
        succeeded = true;
        for item in items {
            *counts.entry(item.date).or_default() += item.count;
        }
    }
    if let Ok(Ok(items)) = gitlab_task.await {
        succeeded = true;
        for item in items {
            *counts.entry(item.date).or_default() += item.count;
        }
    }
    if !succeeded {
        return Err(
            "Không thể tải lịch đóng góp từ GitHub hoặc GitLab. Hãy kiểm tra phiên đăng nhập CLI."
                .into(),
        );
    }
    let mut items = counts
        .into_iter()
        .map(|(date, count)| ContributionDay { date, count })
        .collect::<Vec<_>>();
    items.sort_by(|left, right| left.date.cmp(&right.date));
    Ok(items)
}

#[tauri::command]
async fn auto_focus_today(
    store: State<'_, AppStore>,
    date: String,
) -> Result<AutoFocusResult, String> {
    let target_date = NaiveDate::parse_from_str(&date, "%Y-%m-%d")
        .map_err(|_| "Ngày tự kiểm tra Focus không hợp lệ.".to_string())?;
    let snapshot = store.snapshot()?;
    let local_repositories = snapshot
        .repositories
        .iter()
        .filter_map(|repository| {
            repository
                .tracking
                .local_path
                .clone()
                .map(|path| (repository.id.clone(), path))
        })
        .collect::<Vec<_>>();
    let should_check_github = snapshot
        .repositories
        .iter()
        .any(|repository| repository.provider.eq_ignore_ascii_case("github"));
    let should_check_gitlab = snapshot
        .repositories
        .iter()
        .any(|repository| repository.provider.eq_ignore_ascii_case("gitlab"));

    let local_task = tauri::async_runtime::spawn_blocking(move || {
        local_repositories
            .into_iter()
            .filter_map(|(repository_id, path)| {
                git::local_activity_on_date(&path, target_date)
                    .ok()
                    .map(|activity| (repository_id, activity))
            })
            .collect::<Vec<_>>()
    });
    let github_task = should_check_github.then(|| {
        let remote_date = date.clone();
        tauri::async_runtime::spawn_blocking(move || github::activity_for_date(&remote_date))
    });
    let gitlab_task = should_check_gitlab.then(|| {
        let remote_date = date.clone();
        tauri::async_runtime::spawn_blocking(move || gitlab::activity_for_date(&remote_date))
    });

    let local_activity = local_task.await.map_err(|error| error.to_string())?;
    let mut remote_activity = Vec::new();
    if let Some(task) = github_task {
        if let Ok(Ok(activity)) = task.await {
            remote_activity.extend(activity);
        }
    }
    if let Some(task) = gitlab_task {
        if let Ok(Ok(activity)) = task.await {
            remote_activity.extend(activity);
        }
    }

    let mut git_statuses = HashMap::new();
    let mut candidates = HashMap::new();
    for (repository_id, activity) in local_activity {
        let branch = activity.status.branch.clone().unwrap_or_default();
        if activity.has_code_changes {
            candidates.insert(repository_id.clone(), branch);
        }
        git_statuses.insert(repository_id, activity.status);
    }

    remote_activity.sort_by(|left, right| right.committed_at.cmp(&left.committed_at));
    let current = store.snapshot()?;
    let mut remote_candidates = HashMap::new();
    for activity in remote_activity {
        let Some(repository) = current.repositories.iter().find(|repository| {
            repository
                .full_name
                .eq_ignore_ascii_case(&activity.repository_full_name)
        }) else {
            continue;
        };
        remote_candidates
            .entry(repository.id.clone())
            .or_insert(activity.branch);
    }
    candidates.extend(remote_candidates);

    store.apply_auto_focus(git_statuses, candidates)
}

fn merge_with_existing(data: &AppData, mut repository: Repository) -> Repository {
    if let Some(existing) = data.repositories.iter().find(|item| {
        item.id.eq_ignore_ascii_case(&repository.id)
            || item.full_name.eq_ignore_ascii_case(&repository.full_name)
    }) {
        let mut tracking = existing.tracking.clone();
        tracking.local_path = repository.tracking.local_path.take();
        tracking.git_status = repository.tracking.git_status.take();
        tracking.local_branches = repository.tracking.local_branches.take();
        repository.tracking = tracking;
        repository.id = existing.id.clone();
        if repository.description.is_none() {
            repository.description = existing.description.clone();
        }
        if repository.url.is_none() {
            repository.url = existing.url.clone();
        }
        if repository.primary_language.is_none() {
            repository.primary_language = existing.primary_language.clone();
        }
    }
    repository
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _, _| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.unminimize();
                let _ = window.set_focus();
            }
        }))
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            let data_path = app
                .path()
                .app_data_dir()
                .map_err(|error| error.to_string())?
                .join("repositories.windows.json");
            let store = AppStore::load(data_path)?;
            app.manage(store);
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            load_data,
            save_repository,
            remove_repository,
            save_settings,
            import_repository,
            scan_repositories,
            auto_detect_local_repository,
            bootstrap_local_repositories,
            refresh_git,
            list_commits,
            list_commits_for_branch,
            list_local_branches,
            git_action,
            switch_git_branch,
            commit_all_git_changes,
            merge_git_branch,
            revert_git_commit,
            git_conflict_state,
            resolve_git_conflict,
            continue_git_conflict_operation,
            abort_git_conflict_operation,
            clone_repository,
            sync_github,
            sync_gitlab,
            github_activity,
            gitlab_activity,
            contribution_calendar,
            auto_focus_today
        ])
        .run(tauri::generate_context!())
        .expect("error while running RepoFocus");
}

#[cfg(test)]
mod tests {
    use super::models::{AppData, Tracking};

    #[test]
    fn defaults_are_safe_and_empty() {
        let data = AppData::default();
        let tracking = Tracking::default();
        assert!(data.repositories.is_empty());
        assert_eq!(tracking.status, "inbox");
        assert_eq!(tracking.priority, "medium");
        assert_eq!(tracking.progress, 0);
    }
}
