use crate::models::{ContributionDay, RemoteActivity, Repository, Tracking};
use chrono::{DateTime, Duration, Local, NaiveDate, Utc};
use serde::Deserialize;
use std::{
    collections::HashMap,
    process::{Command, Output, Stdio},
};

#[derive(Debug, Clone, Deserialize)]
struct GlabProject {
    id: i64,
    name: String,
    path_with_namespace: String,
    web_url: String,
    description: Option<String>,
    visibility: String,
    archived: bool,
    default_branch: Option<String>,
    open_issues_count: Option<u32>,
    last_activity_at: DateTime<Utc>,
    updated_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Deserialize)]
struct GlabEvent {
    project_id: i64,
    created_at: DateTime<Utc>,
    push_data: Option<GlabPushData>,
}

#[derive(Debug, Deserialize)]
struct GlabPushData {
    ref_type: Option<String>,
    commit_from: Option<String>,
    commit_to: Option<String>,
    #[serde(rename = "ref")]
    branch: Option<String>,
    commit_title: Option<String>,
}

#[derive(Debug, Deserialize)]
struct GlabComparison {
    commits: Vec<GlabCommit>,
}

#[derive(Debug, Deserialize)]
struct GlabCommit {
    id: String,
    title: String,
    message: Option<String>,
    author_name: Option<String>,
    committed_date: Option<DateTime<Utc>>,
}

pub fn list_repositories() -> Result<Vec<Repository>, String> {
    Ok(list_projects()?
        .into_iter()
        .map(|project| Repository {
            id: format!("gitlab:{}", project.id),
            name: project.name,
            full_name: project.path_with_namespace,
            description: project.description,
            url: Some(project.web_url),
            provider: "gitlab".into(),
            is_private: matches!(project.visibility.as_str(), "private" | "internal"),
            is_archived: project.archived,
            primary_language: None,
            default_branch: project.default_branch,
            open_issue_count: project.open_issues_count.unwrap_or(0),
            open_pull_request_count: 0,
            pushed_at: Some(project.last_activity_at),
            updated_at: project.updated_at.unwrap_or(project.last_activity_at),
            tracking: Tracking::default(),
        })
        .collect())
}

pub fn contribution_calendar(days: u32) -> Result<Vec<ContributionDay>, String> {
    ensure_authenticated()?;
    let days = days.clamp(7, 366);
    let today = Local::now().date_naive();
    let start = today
        .checked_sub_signed(Duration::days(i64::from(days.saturating_sub(1))))
        .ok_or_else(|| "Khoảng ngày lịch đóng góp GitLab không hợp lệ.".to_string())?;
    let tomorrow = today
        .checked_add_signed(Duration::days(1))
        .ok_or_else(|| "Khoảng ngày lịch đóng góp GitLab không hợp lệ.".to_string())?;
    let mut counts = HashMap::<String, u32>::new();
    let mut page = 1;
    loop {
        let endpoint = format!(
            "events?action=pushed&scope=all&after={}&before={}&sort=desc&per_page=100&page={page}",
            start.format("%Y-%m-%d"),
            tomorrow.format("%Y-%m-%d")
        );
        let output = run_glab(["api", endpoint.as_str(), "--hostname", "gitlab.com"])?;
        let events: Vec<GlabEvent> = serde_json::from_slice(&output.stdout)
            .map_err(|error| format!("GitLab CLI trả về lịch đóng góp không hợp lệ: {error}"))?;
        let count = events.len();
        for event in events {
            let date = event.created_at.with_timezone(&Local).date_naive();
            if date < start || date > today {
                continue;
            }
            let key = date.format("%Y-%m-%d").to_string();
            *counts.entry(key).or_default() += 1;
        }
        if count < 100 {
            break;
        }
        page += 1;
    }
    Ok(counts
        .into_iter()
        .map(|(date, count)| ContributionDay { date, count })
        .collect())
}

pub fn activity_for_date(date: &str) -> Result<Vec<RemoteActivity>, String> {
    let target = NaiveDate::parse_from_str(date, "%Y-%m-%d")
        .map_err(|_| "Ngày hoạt động GitLab không hợp lệ.".to_string())?;
    let next = target
        .checked_add_signed(Duration::days(1))
        .ok_or_else(|| "Ngày hoạt động GitLab không hợp lệ.".to_string())?;
    let projects = list_projects()?;
    let names = projects
        .into_iter()
        .map(|project| (project.id, project.path_with_namespace))
        .collect::<HashMap<_, _>>();

    let mut events = Vec::new();
    let mut page = 1;
    loop {
        let endpoint = format!(
            "events?action=pushed&scope=all&after={}&before={}&sort=desc&per_page=100&page={page}",
            target.format("%Y-%m-%d"),
            next.format("%Y-%m-%d")
        );
        let output = run_glab(["api", endpoint.as_str(), "--hostname", "gitlab.com"])?;
        let page_events: Vec<GlabEvent> = serde_json::from_slice(&output.stdout)
            .map_err(|error| format!("GitLab CLI trả về activity không hợp lệ: {error}"))?;
        let count = page_events.len();
        events.extend(page_events);
        if count < 100 {
            break;
        }
        page += 1;
    }

    let mut activity = Vec::new();
    for event in events {
        if event.created_at.with_timezone(&Local).date_naive() != target {
            continue;
        }
        let Some(push) = event.push_data else {
            continue;
        };
        if push.ref_type.as_deref() != Some("branch") {
            continue;
        }
        let branch = push
            .branch
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "main".into());
        let repository_full_name = names
            .get(&event.project_id)
            .cloned()
            .unwrap_or_else(|| format!("GitLab project {}", event.project_id));

        let mut commits = compare_commits(
            event.project_id,
            push.commit_from.as_deref(),
            push.commit_to.as_deref(),
        )
        .unwrap_or_default();
        if commits.is_empty() {
            if let Some(sha) = push.commit_to.filter(|value| !value.is_empty()) {
                commits.push(GlabCommit {
                    id: sha,
                    title: push
                        .commit_title
                        .unwrap_or_else(|| "Đẩy code lên GitLab".into()),
                    message: None,
                    author_name: None,
                    committed_date: None,
                });
            }
        }

        for commit in commits {
            let subject = commit
                .message
                .as_deref()
                .and_then(|message| message.lines().next())
                .filter(|line| !line.trim().is_empty())
                .unwrap_or(&commit.title)
                .to_string();
            activity.push(RemoteActivity {
                repository_full_name: repository_full_name.clone(),
                branch: branch.clone(),
                sha: commit.id,
                subject,
                author: commit.author_name.unwrap_or_else(|| "GitLab".into()),
                committed_at: commit.committed_date.unwrap_or(event.created_at),
            });
        }
    }
    activity.sort_by(|left, right| right.committed_at.cmp(&left.committed_at));
    Ok(activity)
}

fn list_projects() -> Result<Vec<GlabProject>, String> {
    ensure_authenticated()?;
    let mut projects = Vec::new();
    let mut page = 1;
    loop {
        let endpoint = format!(
            "projects?membership=true&per_page=100&page={page}&order_by=last_activity_at&sort=desc"
        );
        let output = run_glab(["api", endpoint.as_str(), "--hostname", "gitlab.com"])?;
        let page_projects: Vec<GlabProject> = serde_json::from_slice(&output.stdout)
            .map_err(|error| format!("GitLab CLI trả về repository không hợp lệ: {error}"))?;
        let count = page_projects.len();
        projects.extend(page_projects);
        if count < 100 {
            break;
        }
        page += 1;
    }
    Ok(projects)
}

fn compare_commits(
    project_id: i64,
    from: Option<&str>,
    to: Option<&str>,
) -> Result<Vec<GlabCommit>, String> {
    let (Some(from), Some(to)) = (from, to) else {
        return Ok(Vec::new());
    };
    if is_zero_sha(from) || is_zero_sha(to) {
        return Ok(Vec::new());
    }
    let endpoint =
        format!("projects/{project_id}/repository/compare?from={from}&to={to}&straight=true");
    let output = run_glab(["api", endpoint.as_str(), "--hostname", "gitlab.com"])?;
    let comparison: GlabComparison = serde_json::from_slice(&output.stdout)
        .map_err(|error| format!("GitLab compare trả về dữ liệu không hợp lệ: {error}"))?;
    Ok(comparison.commits)
}

fn ensure_authenticated() -> Result<(), String> {
    let output = glab_command()
        .args(["auth", "status", "--hostname", "gitlab.com"])
        .output()
        .map_err(|error| {
            format!("Không chạy được GitLab CLI. Hãy cài `glab` và chạy `glab auth login`: {error}")
        })?;
    if output.status.success() {
        Ok(())
    } else {
        let error = output_error(&output);
        Err(format!("{error} Hãy chạy `glab auth login --hostname gitlab.com` nếu phiên đăng nhập đã hết hạn."))
    }
}

fn run_glab<const N: usize>(args: [&str; N]) -> Result<Output, String> {
    let output = glab_command().args(args).output().map_err(|error| {
        format!("Không chạy được GitLab CLI. Hãy cài `glab` và chạy `glab auth login`: {error}")
    })?;
    if output.status.success() {
        Ok(output)
    } else {
        Err(output_error(&output))
    }
}

fn output_error(output: &Output) -> String {
    let error = String::from_utf8_lossy(&output.stderr).trim().to_string();
    if error.is_empty() {
        String::from_utf8_lossy(&output.stdout).trim().to_string()
    } else {
        error
    }
}

fn is_zero_sha(value: &str) -> bool {
    !value.is_empty() && value.bytes().all(|byte| byte == b'0')
}

fn glab_command() -> Command {
    let mut command = Command::new("glab");
    command
        .env("LC_ALL", "C")
        .env("NO_PROMPT", "1")
        .env("GITLAB_HOST", "gitlab.com")
        .env("GL_HOST", "gitlab.com")
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
