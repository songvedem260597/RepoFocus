use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct GitStatus {
    pub branch: Option<String>,
    pub has_upstream: bool,
    pub ahead_count: u32,
    pub behind_count: u32,
    pub changed_file_count: u32,
    pub conflict_count: u32,
    pub checked_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CommitInfo {
    pub sha: String,
    pub subject: String,
    pub author: String,
    pub committed_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum PlanCompletionSource {
    Manual,
    Commit,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct RepositoryPlanItem {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub commit_keyword: String,
    #[serde(default)]
    pub estimated_minutes: Option<u32>,
    #[serde(default)]
    pub is_completed: bool,
    #[serde(default)]
    pub completion_source: Option<PlanCompletionSource>,
    #[serde(default)]
    pub matched_commit_sha: Option<String>,
    #[serde(default)]
    pub created_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub completed_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RepositoryBranchTracking {
    #[serde(default)]
    pub branch_name: String,
    #[serde(default = "default_status")]
    pub status: String,
    #[serde(default = "default_priority")]
    pub priority: String,
    #[serde(default)]
    pub progress: u8,
    #[serde(default)]
    pub next_action: String,
    #[serde(default)]
    pub notes: String,
    #[serde(default)]
    pub deadline: Option<String>,
    #[serde(default)]
    pub uses_outline_plan: bool,
    #[serde(default)]
    pub plan_items: Vec<RepositoryPlanItem>,
    #[serde(default)]
    pub manual_progress: Option<u8>,
    #[serde(default = "Utc::now")]
    pub modified_at: DateTime<Utc>,
}

impl Default for RepositoryBranchTracking {
    fn default() -> Self {
        Self {
            branch_name: String::new(),
            status: default_status(),
            priority: default_priority(),
            progress: 0,
            next_action: String::new(),
            notes: String::new(),
            deadline: None,
            uses_outline_plan: false,
            plan_items: Vec::new(),
            manual_progress: None,
            modified_at: Utc::now(),
        }
    }
}

impl RepositoryBranchTracking {
    fn normalize(&mut self) {
        self.branch_name = self.branch_name.trim().to_string();
        self.progress = self.progress.min(100);
        self.manual_progress = self.manual_progress.map(|progress| progress.min(100));
        normalize_plan_items(&mut self.plan_items);
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Tracking {
    pub status: String,
    pub priority: String,
    pub progress: u8,
    pub next_action: String,
    pub notes: String,
    pub is_focused: bool,
    pub focus_order: i32,
    pub deadline: Option<String>,
    pub local_path: Option<String>,
    pub git_status: Option<GitStatus>,
    #[serde(default)]
    pub uses_outline_plan: bool,
    #[serde(default)]
    pub plan_items: Vec<RepositoryPlanItem>,
    #[serde(default)]
    pub manual_progress: Option<u8>,
    #[serde(default)]
    pub focus_branch: Option<String>,
    #[serde(default)]
    pub local_branches: Option<Vec<String>>,
    #[serde(default)]
    pub branch_trackings: Vec<RepositoryBranchTracking>,
    pub modified_at: DateTime<Utc>,
}

impl Default for Tracking {
    fn default() -> Self {
        Self {
            status: "inbox".into(),
            priority: "medium".into(),
            progress: 0,
            next_action: String::new(),
            notes: String::new(),
            is_focused: false,
            focus_order: 0,
            deadline: None,
            local_path: None,
            git_status: None,
            uses_outline_plan: false,
            plan_items: Vec::new(),
            manual_progress: None,
            focus_branch: None,
            local_branches: None,
            branch_trackings: Vec::new(),
            modified_at: Utc::now(),
        }
    }
}

impl Tracking {
    pub fn normalize(&mut self) {
        self.progress = self.progress.min(100);
        self.focus_branch = self
            .focus_branch
            .take()
            .map(|branch| branch.trim().to_string())
            .filter(|branch| !branch.is_empty());
        self.local_branches = self.local_branches.take().map(|branches| {
            let mut branches = branches
                .into_iter()
                .map(|branch| branch.trim().to_string())
                .filter(|branch| !branch.is_empty())
                .collect::<Vec<_>>();
            branches.sort();
            branches.dedup();
            branches
        });
        if self
            .local_branches
            .as_ref()
            .is_some_and(|branches| branches.is_empty())
        {
            self.local_branches = None;
        }
        self.manual_progress = self.manual_progress.map(|progress| progress.min(100));
        normalize_plan_items(&mut self.plan_items);
        let mut branch_trackings = Vec::with_capacity(self.branch_trackings.len());
        for mut branch_tracking in std::mem::take(&mut self.branch_trackings) {
            branch_tracking.normalize();
            if branch_tracking.branch_name.is_empty() {
                continue;
            }
            if let Some(index) =
                branch_trackings
                    .iter()
                    .position(|item: &RepositoryBranchTracking| {
                        item.branch_name
                            .eq_ignore_ascii_case(&branch_tracking.branch_name)
                    })
            {
                branch_trackings[index] = branch_tracking;
            } else {
                branch_trackings.push(branch_tracking);
            }
        }
        self.branch_trackings = branch_trackings;
    }
}

fn default_status() -> String {
    "inbox".into()
}

fn default_priority() -> String {
    "medium".into()
}

fn normalize_plan_items(items: &mut [RepositoryPlanItem]) {
    for item in items {
        item.title = item.title.trim().to_string();
        item.commit_keyword = item.commit_keyword.trim().to_string();
        if item.commit_keyword.is_empty() {
            item.commit_keyword = item.title.clone();
        }
        item.estimated_minutes = item
            .estimated_minutes
            .map(|minutes| minutes.clamp(1, 10_080));
        if !item.is_completed {
            item.completion_source = None;
            item.matched_commit_sha = None;
            item.completed_at = None;
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Repository {
    pub id: String,
    pub name: String,
    pub full_name: String,
    pub description: Option<String>,
    pub url: Option<String>,
    pub provider: String,
    pub is_private: bool,
    pub is_archived: bool,
    pub primary_language: Option<String>,
    pub default_branch: Option<String>,
    #[serde(default)]
    pub open_issue_count: u32,
    #[serde(default)]
    pub open_pull_request_count: u32,
    pub pushed_at: Option<DateTime<Utc>>,
    pub updated_at: DateTime<Utc>,
    pub tracking: Tracking,
}

impl Repository {
    pub fn normalize_tracking(&mut self) {
        self.tracking.normalize();
        self.migrate_focus_branch_tracking();
        let repository_id = self.id.clone();
        for (index, item) in self.tracking.plan_items.iter_mut().enumerate() {
            if item.id.trim().is_empty() {
                item.id = format!("migrated-{repository_id}-{index}");
            }
        }
        for branch_tracking in &mut self.tracking.branch_trackings {
            let branch_name = branch_tracking
                .branch_name
                .replace(|character: char| !character.is_ascii_alphanumeric(), "-");
            for (index, item) in branch_tracking.plan_items.iter_mut().enumerate() {
                if item.id.trim().is_empty() {
                    item.id = format!("migrated-{repository_id}-{branch_name}-{index}");
                }
            }
        }
    }

    fn migrate_focus_branch_tracking(&mut self) {
        if !self.tracking.is_focused {
            return;
        }

        let branch_name = self
            .tracking
            .focus_branch
            .clone()
            .or_else(|| {
                self.tracking
                    .git_status
                    .as_ref()
                    .and_then(|status| status.branch.clone())
            })
            .or_else(|| self.default_branch.clone())
            .map(|branch| branch.trim().to_string())
            .filter(|branch| !branch.is_empty())
            .unwrap_or_else(|| "main".into());

        self.tracking.focus_branch = Some(branch_name.clone());
        if let Some(snapshot) = self
            .tracking
            .branch_trackings
            .iter()
            .find(|item| item.branch_name.eq_ignore_ascii_case(&branch_name))
            .cloned()
        {
            self.tracking.status = snapshot.status;
            self.tracking.priority = snapshot.priority;
            self.tracking.progress = snapshot.progress;
            self.tracking.next_action = snapshot.next_action;
            self.tracking.notes = snapshot.notes;
            self.tracking.deadline = snapshot.deadline;
            self.tracking.uses_outline_plan = snapshot.uses_outline_plan;
            self.tracking.plan_items = snapshot.plan_items;
            self.tracking.manual_progress = snapshot.manual_progress;
        } else {
            self.tracking
                .branch_trackings
                .push(RepositoryBranchTracking {
                    branch_name,
                    status: self.tracking.status.clone(),
                    priority: self.tracking.priority.clone(),
                    progress: self.tracking.progress,
                    next_action: self.tracking.next_action.clone(),
                    notes: self.tracking.notes.clone(),
                    deadline: self.tracking.deadline.clone(),
                    uses_outline_plan: self.tracking.uses_outline_plan,
                    plan_items: self.tracking.plan_items.clone(),
                    manual_progress: self.tracking.manual_progress,
                    modified_at: self.tracking.modified_at,
                });
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Settings {
    pub theme: String,
    pub language: String,
    pub scan_depth: u8,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            theme: "system".into(),
            language: "vi".into(),
            scan_depth: 4,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppData {
    pub version: u32,
    pub repositories: Vec<Repository>,
    pub last_sync_at: Option<DateTime<Utc>>,
    pub settings: Settings,
}

impl Default for AppData {
    fn default() -> Self {
        Self {
            version: Self::CURRENT_VERSION,
            repositories: Vec::new(),
            last_sync_at: None,
            settings: Settings::default(),
        }
    }
}

impl AppData {
    pub const CURRENT_VERSION: u32 = 4;

    /// Migrates legacy persisted data in memory. The next normal save writes the
    /// normalized v4 form, while loading remains non-destructive.
    pub fn migrate(&mut self) {
        self.version = self.version.max(Self::CURRENT_VERSION);
        for repository in &mut self.repositories {
            repository.normalize_tracking();
        }
    }

    pub fn auto_focus_repositories(
        &mut self,
        candidates: &HashMap<String, String>,
        modified_at: DateTime<Utc>,
    ) -> Vec<String> {
        let mut candidate_ids = candidates.keys().cloned().collect::<Vec<_>>();
        candidate_ids.sort();
        let mut next_focus_order = self
            .repositories
            .iter()
            .filter(|repository| repository.tracking.is_focused)
            .map(|repository| repository.tracking.focus_order)
            .max()
            .unwrap_or(-1)
            .saturating_add(1);
        let mut focused_repository_ids = Vec::new();

        for repository_id in candidate_ids {
            let Some(repository) = self
                .repositories
                .iter_mut()
                .find(|repository| repository.id == repository_id)
            else {
                continue;
            };
            if repository.is_archived
                || repository.tracking.status == "archived"
                || repository.tracking.is_focused
            {
                continue;
            }

            let branch = candidates
                .get(&repository_id)
                .map(String::as_str)
                .map(str::trim)
                .filter(|branch| !branch.is_empty())
                .map(str::to_string)
                .or_else(|| {
                    repository
                        .tracking
                        .git_status
                        .as_ref()
                        .and_then(|status| status.branch.clone())
                })
                .or_else(|| repository.default_branch.clone())
                .unwrap_or_else(|| "main".into());

            repository.tracking.is_focused = true;
            repository.tracking.focus_order = next_focus_order;
            repository.tracking.focus_branch = Some(branch);
            repository.tracking.modified_at = modified_at;
            repository.normalize_tracking();
            focused_repository_ids.push(repository_id);
            next_focus_order = next_focus_order.saturating_add(1);
        }

        focused_repository_ids
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ScanResult {
    pub repositories: Vec<Repository>,
    pub visited_folders: u32,
    pub skipped_folders: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GitActionResult {
    pub message: String,
    pub status: GitStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GitConflictState {
    pub files: Vec<String>,
    pub sequence: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteActivity {
    pub repository_full_name: String,
    pub branch: String,
    pub sha: String,
    pub subject: String,
    pub author: String,
    pub committed_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AutoFocusResult {
    pub data: AppData,
    pub focused_repository_ids: Vec<String>,
}

#[cfg(test)]
mod tests {
    use super::{
        AppData, PlanCompletionSource, Repository, RepositoryPlanItem, Settings, Tracking,
    };
    use chrono::Utc;
    use std::collections::HashMap;

    #[test]
    fn legacy_tracking_gets_outline_defaults_without_losing_data() {
        let tracking: Tracking = serde_json::from_str(
            r#"{
                "status": "active",
                "priority": "high",
                "progress": 65,
                "nextAction": "Ship the inspector",
                "notes": "Keep this note",
                "isFocused": true,
                "focusOrder": 2,
                "deadline": null,
                "localPath": null,
                "gitStatus": null,
                "modifiedAt": "2026-07-25T00:00:00Z"
            }"#,
        )
        .expect("legacy tracking should deserialize");

        assert!(!tracking.uses_outline_plan);
        assert!(tracking.plan_items.is_empty());
        assert_eq!(tracking.focus_branch, None);
        assert_eq!(tracking.local_branches, None);
        assert_eq!(tracking.next_action, "Ship the inspector");
    }

    #[test]
    fn plan_items_round_trip_with_camel_case_fields() {
        let mut tracking = Tracking::default();
        tracking.uses_outline_plan = true;
        tracking.plan_items.push(RepositoryPlanItem {
            id: "task-1".into(),
            title: "Finish the visual parity pass".into(),
            commit_keyword: "visual parity".into(),
            estimated_minutes: Some(45),
            is_completed: true,
            completion_source: Some(PlanCompletionSource::Commit),
            matched_commit_sha: Some("abc1234".into()),
            created_at: None,
            completed_at: None,
        });

        let json = serde_json::to_value(&tracking).expect("tracking should serialize");
        let item = &json["planItems"][0];
        assert_eq!(item["commitKeyword"], "visual parity");
        assert_eq!(item["matchedCommitSha"], "abc1234");
        assert_eq!(item["completionSource"], "commit");
    }

    #[test]
    fn legacy_focused_repository_gets_a_branch_snapshot() {
        let mut repository: Repository = serde_json::from_str(
            r#"{
                "id": "legacy-focus",
                "name": "Legacy Focus",
                "fullName": "example/legacy-focus",
                "description": null,
                "url": null,
                "provider": "github",
                "isPrivate": false,
                "isArchived": false,
                "primaryLanguage": null,
                "defaultBranch": "backend",
                "pushedAt": null,
                "updatedAt": "2026-07-25T00:00:00Z",
                "tracking": {
                    "status": "active",
                    "priority": "high",
                    "progress": 65,
                    "nextAction": "Ship the inspector",
                    "notes": "Keep this note",
                    "isFocused": true,
                    "focusOrder": 2,
                    "deadline": null,
                    "localPath": null,
                    "gitStatus": null,
                    "modifiedAt": "2026-07-25T00:00:00Z"
                }
            }"#,
        )
        .expect("legacy repository should deserialize");

        repository.normalize_tracking();

        assert_eq!(repository.tracking.focus_branch.as_deref(), Some("backend"));
        assert_eq!(repository.tracking.branch_trackings.len(), 1);
        let snapshot = &repository.tracking.branch_trackings[0];
        assert_eq!(snapshot.branch_name, "backend");
        assert_eq!(snapshot.status, "active");
        assert_eq!(snapshot.next_action, "Ship the inspector");
    }

    #[test]
    fn auto_focus_preserves_tracking_and_skips_archived_repositories() {
        let repository = |id: &str, focus_order: i32| Repository {
            id: id.into(),
            name: id.into(),
            full_name: format!("example/{id}"),
            description: None,
            url: None,
            provider: "github".into(),
            is_private: false,
            is_archived: false,
            primary_language: None,
            default_branch: Some("main".into()),
            open_issue_count: 0,
            open_pull_request_count: 0,
            pushed_at: None,
            updated_at: Utc::now(),
            tracking: Tracking {
                focus_order,
                notes: format!("notes-{id}"),
                ..Tracking::default()
            },
        };
        let mut already_focused = repository("focused", 4);
        already_focused.tracking.is_focused = true;
        already_focused.tracking.focus_branch = Some("existing".into());
        let mut archived = repository("archived", 0);
        archived.tracking.status = "archived".into();
        let mut data = AppData {
            version: AppData::CURRENT_VERSION,
            repositories: vec![
                repository("beta", 0),
                archived,
                already_focused,
                repository("alpha", 0),
            ],
            last_sync_at: None,
            settings: Settings::default(),
        };
        let candidates = HashMap::from([
            ("beta".to_string(), "feature/beta".to_string()),
            ("archived".to_string(), "main".to_string()),
            ("focused".to_string(), "changed".to_string()),
            ("alpha".to_string(), "feature/alpha".to_string()),
        ]);

        let focused = data.auto_focus_repositories(&candidates, Utc::now());

        assert_eq!(focused, vec!["alpha", "beta"]);
        let alpha = data
            .repositories
            .iter()
            .find(|repository| repository.id == "alpha")
            .expect("alpha should still exist");
        let beta = data
            .repositories
            .iter()
            .find(|repository| repository.id == "beta")
            .expect("beta should still exist");
        assert_eq!(alpha.tracking.focus_order, 5);
        assert_eq!(beta.tracking.focus_order, 6);
        assert_eq!(alpha.tracking.notes, "notes-alpha");
        assert_eq!(
            alpha.tracking.focus_branch.as_deref(),
            Some("feature/alpha")
        );
        assert_eq!(alpha.tracking.branch_trackings.len(), 1);
        let focused = data
            .repositories
            .iter()
            .find(|repository| repository.id == "focused")
            .expect("focused repository should still exist");
        assert_eq!(focused.tracking.focus_order, 4);
        assert_eq!(focused.tracking.focus_branch.as_deref(), Some("existing"));
        let archived = data
            .repositories
            .iter()
            .find(|repository| repository.id == "archived")
            .expect("archived repository should still exist");
        assert!(!archived.tracking.is_focused);
    }
}
