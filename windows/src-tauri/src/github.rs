use crate::models::{RemoteActivity, Repository, Tracking};
use chrono::{DateTime, Local, Utc};
use serde::Deserialize;
use std::process::{Command, Stdio};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct GhRepository {
    name: String,
    name_with_owner: String,
    url: String,
    description: Option<String>,
    is_private: bool,
    is_archived: bool,
    primary_language: Option<GhLanguage>,
    default_branch_ref: Option<GhBranchRef>,
    issues: Option<GhCount>,
    pull_requests: Option<GhCount>,
    pushed_at: Option<DateTime<Utc>>,
    updated_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
struct GhLanguage {
    name: String,
}

#[derive(Debug, Deserialize)]
struct GhBranchRef {
    name: String,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct GhCount {
    total_count: u32,
}

#[derive(Debug, Deserialize)]
struct GhEvent {
    #[serde(rename = "type")]
    event_type: String,
    created_at: DateTime<Utc>,
    repo: GhEventRepository,
    payload: Option<GhPushPayload>,
}

#[derive(Debug, Deserialize)]
struct GhEventRepository {
    name: String,
}

#[derive(Debug, Deserialize)]
struct GhPushPayload {
    #[serde(rename = "ref")]
    branch_ref: Option<String>,
    head: Option<String>,
    commits: Option<Vec<GhPushCommit>>,
}

#[derive(Debug, Deserialize)]
struct GhPushCommit {
    sha: String,
    message: String,
    author: Option<GhEventAuthor>,
}

#[derive(Debug, Deserialize)]
struct GhEventAuthor {
    name: Option<String>,
}

pub fn list_repositories() -> Result<Vec<Repository>, String> {
    let output = gh_command()
        .args([
            "repo",
            "list",
            "--limit",
            "1000",
            "--json",
            "name,nameWithOwner,url,description,isPrivate,isArchived,primaryLanguage,defaultBranchRef,issues,pullRequests,pushedAt,updatedAt",
        ])
        .output()
        .map_err(|error| {
            format!(
                "Không chạy được GitHub CLI. Hãy cài `gh` và đăng nhập bằng `gh auth login`: {error}"
            )
        })?;

    if !output.status.success() {
        let error = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let hint = if error.to_lowercase().contains("auth")
            || error.to_lowercase().contains("token")
            || error.to_lowercase().contains("login")
        {
            " Phiên GitHub đã hết hạn; hãy chạy `gh auth login -h github.com` trong Terminal."
        } else {
            ""
        };
        return Err(format!("{error}{hint}"));
    }

    let repositories: Vec<GhRepository> = serde_json::from_slice(&output.stdout)
        .map_err(|error| format!("GitHub CLI trả về dữ liệu không hợp lệ: {error}"))?;

    Ok(repositories
        .into_iter()
        .map(|repository| Repository {
            id: format!("github:{}", repository.name_with_owner.to_lowercase()),
            name: repository.name,
            full_name: repository.name_with_owner,
            description: repository.description,
            url: Some(repository.url),
            provider: "github".into(),
            is_private: repository.is_private,
            is_archived: repository.is_archived,
            primary_language: repository.primary_language.map(|language| language.name),
            default_branch: repository.default_branch_ref.map(|branch| branch.name),
            open_issue_count: repository.issues.unwrap_or_default().total_count,
            open_pull_request_count: repository.pull_requests.unwrap_or_default().total_count,
            pushed_at: repository.pushed_at,
            updated_at: repository.updated_at,
            tracking: Tracking::default(),
        })
        .collect())
}

pub fn activity_for_date(date: &str) -> Result<Vec<RemoteActivity>, String> {
    let login_output = gh_command()
        .args(["api", "user", "--jq", ".login"])
        .output()
        .map_err(|error| format!("Không chạy được GitHub CLI: {error}"))?;
    if !login_output.status.success() {
        let error = String::from_utf8_lossy(&login_output.stderr)
            .trim()
            .to_string();
        return Err(format!(
            "{error} Hãy chạy `gh auth login -h github.com` nếu phiên đăng nhập đã hết hạn."
        ));
    }
    let login = String::from_utf8_lossy(&login_output.stdout)
        .trim()
        .to_string();
    if login.is_empty() {
        return Err("GitHub CLI không trả về username hiện tại.".into());
    }

    let endpoint = format!("users/{login}/events");
    let output = gh_command()
        .args(["api", &endpoint, "--paginate", "--jq", ".[]"])
        .output()
        .map_err(|error| format!("Không chạy được GitHub CLI: {error}"))?;

    if !output.status.success() {
        let error = String::from_utf8_lossy(&output.stderr).trim().to_string();
        return Err(format!(
            "{error} Hãy chạy `gh auth login -h github.com` nếu phiên đăng nhập đã hết hạn."
        ));
    }

    let mut activity = Vec::new();
    for line in String::from_utf8_lossy(&output.stdout).lines() {
        let Ok(event) = serde_json::from_str::<GhEvent>(line) else {
            continue;
        };
        if event.event_type != "PushEvent"
            || event
                .created_at
                .with_timezone(&Local)
                .date_naive()
                .to_string()
                != date
        {
            continue;
        }

        let Some(payload) = event.payload else {
            continue;
        };
        let branch = payload
            .branch_ref
            .unwrap_or_default()
            .trim_start_matches("refs/heads/")
            .to_string();
        let branch = if branch.is_empty() {
            "main".into()
        } else {
            branch
        };
        let commits = payload.commits.unwrap_or_default();
        if commits.is_empty() {
            if let Some(sha) = payload.head {
                activity.push(RemoteActivity {
                    repository_full_name: event.repo.name.clone(),
                    branch,
                    sha,
                    subject: "Đẩy code lên GitHub".into(),
                    author: "GitHub".into(),
                    committed_at: event.created_at,
                });
            }
        } else {
            for commit in commits {
                activity.push(RemoteActivity {
                    repository_full_name: event.repo.name.clone(),
                    branch: branch.clone(),
                    sha: commit.sha,
                    subject: commit
                        .message
                        .lines()
                        .next()
                        .unwrap_or_default()
                        .to_string(),
                    author: commit
                        .author
                        .and_then(|author| author.name)
                        .unwrap_or_else(|| "GitHub".into()),
                    committed_at: event.created_at,
                });
            }
        }
    }
    Ok(activity)
}

fn gh_command() -> Command {
    let mut command = Command::new("gh");
    command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(0x08000000);
    }
    command
}
