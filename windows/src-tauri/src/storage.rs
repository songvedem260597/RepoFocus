use crate::models::{AppData, Repository, Settings};
use std::{
    fs,
    path::PathBuf,
    sync::{Arc, Mutex},
};

#[derive(Clone)]
pub struct AppStore {
    path: PathBuf,
    data: Arc<Mutex<AppData>>,
}

impl AppStore {
    pub fn load(path: PathBuf) -> Result<Self, String> {
        let mut data = if path.exists() {
            let raw = fs::read_to_string(&path)
                .map_err(|error| format!("Không thể đọc dữ liệu RepoFocus: {error}"))?;
            serde_json::from_str(&raw)
                .map_err(|error| format!("Dữ liệu RepoFocus không hợp lệ: {error}"))?
        } else {
            AppData::default()
        };
        data.migrate();

        Ok(Self {
            path,
            data: Arc::new(Mutex::new(data)),
        })
    }

    pub fn snapshot(&self) -> Result<AppData, String> {
        self.data
            .lock()
            .map(|data| data.clone())
            .map_err(|_| "Không thể khóa dữ liệu RepoFocus.".to_string())
    }

    pub fn replace(&self, mut data: AppData) -> Result<(), String> {
        data.migrate();
        {
            let mut current = self
                .data
                .lock()
                .map_err(|_| "Không thể khóa dữ liệu RepoFocus.".to_string())?;
            *current = data;
        }
        self.persist()
    }

    pub fn upsert(&self, mut repository: Repository) -> Result<AppData, String> {
        repository.normalize_tracking();
        {
            let mut data = self
                .data
                .lock()
                .map_err(|_| "Không thể khóa dữ liệu RepoFocus.".to_string())?;
            if let Some(existing) = data
                .repositories
                .iter_mut()
                .find(|item| item.id == repository.id)
            {
                *existing = repository;
            } else {
                data.repositories.push(repository);
            }
        }
        self.persist()?;
        self.snapshot()
    }

    pub fn remove(&self, repository_id: &str) -> Result<AppData, String> {
        {
            let mut data = self
                .data
                .lock()
                .map_err(|_| "Không thể khóa dữ liệu RepoFocus.".to_string())?;
            data.repositories.retain(|item| item.id != repository_id);
        }
        self.persist()?;
        self.snapshot()
    }

    pub fn update_settings(&self, settings: Settings) -> Result<AppData, String> {
        {
            let mut data = self
                .data
                .lock()
                .map_err(|_| "Không thể khóa dữ liệu RepoFocus.".to_string())?;
            data.settings = settings;
        }
        self.persist()?;
        self.snapshot()
    }

    pub fn persist(&self) -> Result<(), String> {
        let data = self.snapshot()?;
        let parent = self
            .path
            .parent()
            .ok_or_else(|| "Đường dẫn dữ liệu không hợp lệ.".to_string())?;
        fs::create_dir_all(parent)
            .map_err(|error| format!("Không thể tạo thư mục dữ liệu: {error}"))?;
        let json = serde_json::to_string_pretty(&data)
            .map_err(|error| format!("Không thể mã hóa dữ liệu: {error}"))?;
        fs::write(&self.path, json)
            .map_err(|error| format!("Không thể lưu dữ liệu RepoFocus: {error}"))
    }
}
