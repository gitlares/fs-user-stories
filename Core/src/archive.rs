// SPDX-License-Identifier: MIT

use std::{
    collections::BTreeMap,
    fs,
    path::{Component, Path},
    thread,
    time::Duration,
};

use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};

use crate::protocol::CoreError;

pub const ARCHIVE_DIRECTORY: &str = ".fs-user-stories";
pub type AttachmentSources = BTreeMap<String, String>;

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProjectSnapshot {
    pub format_version: u32,
    pub project_id: String,
    pub name: String,
    pub prefix: String,
    #[serde(default)]
    pub actors: Vec<Value>,
    #[serde(default)]
    pub stories: Vec<Value>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProjectHeader<'a> {
    format_version: u32,
    project_id: &'a str,
    name: &'a str,
    prefix: &'a str,
}

impl ProjectSnapshot {
    pub const FORMAT_VERSION: u32 = 1;

    pub fn validate(&self) -> Result<(), CoreError> {
        if self.format_version != Self::FORMAT_VERSION {
            return Err(CoreError::UnsupportedArchive(self.format_version));
        }
        if self.project_id.trim().is_empty() || self.name.trim().is_empty() {
            return Err(CoreError::InvalidArchive(
                "Project identity is missing".into(),
            ));
        }
        for entity in self.actors.iter().chain(self.stories.iter()) {
            entity_id(entity)?;
        }
        Ok(())
    }

    pub fn digest(&self) -> Result<String, CoreError> {
        self.validate()?;
        let normalized = serde_json::to_vec(self)?;
        Ok(hex::encode(Sha256::digest(normalized)))
    }

    pub fn write(&self, repository: &Path) -> Result<String, CoreError> {
        self.write_with_attachments(repository, &AttachmentSources::new())
    }

    pub fn write_with_attachments(
        &self,
        repository: &Path,
        attachment_sources: &AttachmentSources,
    ) -> Result<String, CoreError> {
        self.validate()?;
        let root = repository.join(ARCHIVE_DIRECTORY);
        let temporary = repository.join(format!("{ARCHIVE_DIRECTORY}.tmp"));
        if temporary.exists() {
            remove_dir_all_with_retry(&temporary)?;
        }
        fs::create_dir_all(temporary.join("profiles"))?;
        fs::create_dir_all(temporary.join("stories"))?;

        let header = ProjectHeader {
            format_version: self.format_version,
            project_id: &self.project_id,
            name: &self.name,
            prefix: &self.prefix,
        };
        write_json(&temporary.join("project.json"), &header)?;
        write_entities(&temporary.join("profiles"), &self.actors)?;
        write_entities(&temporary.join("stories"), &self.stories)?;
        fs::write(temporary.join("README.md"), self.readme())?;
        // Preserve only attachments still referenced by the snapshot. Sources
        // supplied by the workspace replace them below, while legacy orphaned
        // paths (including paths that embedded long filenames) disappear.
        for relative_path in self.referenced_attachment_paths()? {
            if attachment_sources.contains_key(&relative_path) {
                continue;
            }
            let relative_path = safe_relative_path(&relative_path)?;
            let source = root.join(relative_path);
            if source.is_file() {
                let destination = temporary.join(relative_path);
                if let Some(parent) = destination.parent() {
                    fs::create_dir_all(parent)?;
                }
                fs::copy(source, destination)?;
            }
        }
        for (relative_path, source_path) in attachment_sources {
            let relative_path = safe_relative_path(relative_path)?;
            let destination = temporary.join(relative_path);
            if let Some(parent) = destination.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::copy(source_path, destination)?;
        }

        if root.exists() {
            remove_dir_all_with_retry(&root)?;
        }
        fs::rename(temporary, root)?;
        self.digest()
    }

    pub fn read(repository: &Path) -> Result<Self, CoreError> {
        let root = repository.join(ARCHIVE_DIRECTORY);
        let header: OwnedProjectHeader = read_json(&root.join("project.json"))?;
        let snapshot = Self {
            format_version: header.format_version,
            project_id: header.project_id,
            name: header.name,
            prefix: header.prefix,
            actors: read_entities(&root.join("profiles"))?,
            stories: read_entities(&root.join("stories"))?,
        };
        snapshot.validate()?;
        Ok(snapshot)
    }

    pub fn read_legacy_with_identity(
        repository: &Path,
        identity: &ProjectSnapshot,
    ) -> Result<Self, CoreError> {
        let root = repository.join(ARCHIVE_DIRECTORY);
        if !root.join("README.md").is_file()
            || (!root.join("profiles").is_dir() && !root.join("stories").is_dir())
        {
            return Err(CoreError::ArchiveNotFound);
        }
        let snapshot = Self {
            format_version: Self::FORMAT_VERSION,
            project_id: identity.project_id.clone(),
            name: identity.name.clone(),
            prefix: identity.prefix.clone(),
            actors: read_entities(&root.join("profiles"))?,
            stories: read_entities(&root.join("stories"))?,
        };
        snapshot.validate()?;
        Ok(snapshot)
    }

    fn readme(&self) -> String {
        format!(
            "# {}\n\nFS User Stories project archive.\n\n- Prefix: `{}`\n- Profiles: {}\n- Stories: {}\n\nThe JSON files are the synchronized source of truth.\n",
            self.name,
            self.prefix,
            self.actors.len(),
            self.stories.len()
        )
    }

    fn referenced_attachment_paths(&self) -> Result<Vec<String>, CoreError> {
        let mut paths = Vec::new();
        for story in &self.stories {
            let Some(attachments) = story.get("attachments").and_then(Value::as_array) else {
                continue;
            };
            for attachment in attachments {
                let path = attachment
                    .get("archiveRelativePath")
                    .and_then(Value::as_str)
                    .ok_or_else(|| {
                        CoreError::InvalidArchive("Attachment archive path is missing".into())
                    })?;
                safe_relative_path(path)?;
                paths.push(path.to_owned());
            }
        }
        Ok(paths)
    }
}

fn remove_dir_all_with_retry(path: &Path) -> Result<(), CoreError> {
    const RETRY_DELAYS_MS: [u64; 4] = [10, 25, 50, 100];

    for delay_ms in RETRY_DELAYS_MS {
        match fs::remove_dir_all(path) {
            Ok(()) => return Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
            Err(_) => thread::sleep(Duration::from_millis(delay_ms)),
        }
    }

    fs::remove_dir_all(path).map_err(CoreError::from)
}

fn safe_relative_path(value: &str) -> Result<&Path, CoreError> {
    let path = Path::new(value);
    if path.is_absolute()
        || path
            .components()
            .any(|component| !matches!(component, Component::Normal(_)))
    {
        return Err(CoreError::InvalidArchive(
            "Attachment path is unsafe".into(),
        ));
    }
    Ok(path)
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct OwnedProjectHeader {
    format_version: u32,
    project_id: String,
    name: String,
    prefix: String,
}

fn entity_id(value: &Value) -> Result<&str, CoreError> {
    value
        .get("id")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| CoreError::InvalidArchive("Every entity requires an id".into()))
}

fn write_entities(directory: &Path, entities: &[Value]) -> Result<(), CoreError> {
    let mut ordered = BTreeMap::new();
    for entity in entities {
        ordered.insert(entity_id(entity)?.to_owned(), entity);
    }
    for (id, entity) in ordered {
        write_json(&directory.join(format!("{id}.json")), entity)?;
    }
    Ok(())
}

fn read_entities(directory: &Path) -> Result<Vec<Value>, CoreError> {
    if !directory.exists() {
        return Ok(Vec::new());
    }
    let mut paths = fs::read_dir(directory)?
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.extension().and_then(|value| value.to_str()) == Some("json"))
        .collect::<Vec<_>>();
    paths.sort();
    paths.into_iter().map(|path| read_json(&path)).collect()
}

fn write_json<T: Serialize>(path: &Path, value: &T) -> Result<(), CoreError> {
    let mut bytes = serde_json::to_vec_pretty(value)?;
    bytes.push(b'\n');
    fs::write(path, bytes)?;
    Ok(())
}

fn read_json<T: for<'de> Deserialize<'de>>(path: &Path) -> Result<T, CoreError> {
    if !path.exists() {
        return Err(CoreError::ArchiveNotFound);
    }
    Ok(serde_json::from_slice(&fs::read(path)?)?)
}

#[cfg(test)]
mod tests {
    use serde_json::json;
    use tempfile::tempdir;

    use super::*;

    #[test]
    fn archive_round_trip_uses_one_file_per_entity() {
        let directory = tempdir().unwrap();
        let snapshot = ProjectSnapshot {
            format_version: 1,
            project_id: "project".into(),
            name: "Example".into(),
            prefix: "EX".into(),
            actors: vec![json!({"id": "actor", "name": "Developer"})],
            stories: vec![json!({"id": "story", "title": "Login"})],
        };
        snapshot.write(directory.path()).unwrap();
        assert!(
            directory
                .path()
                .join(".fs-user-stories/profiles/actor.json")
                .exists()
        );
        assert!(
            directory
                .path()
                .join(".fs-user-stories/stories/story.json")
                .exists()
        );
        assert_eq!(ProjectSnapshot::read(directory.path()).unwrap(), snapshot);
    }

    #[test]
    fn archive_replaces_legacy_attachment_paths_without_leaving_orphans() {
        let directory = tempdir().unwrap();
        let source = directory.path().join("source.png");
        fs::write(&source, b"image").unwrap();
        let legacy_path = "attachments/story/attachment-Screenshot with a very long name.png";
        let canonical_path =
            "attachments/0123456789abcdef01234567/0123456789abcdef0123456789abcdef.png";
        let snapshot = |path: &str| ProjectSnapshot {
            format_version: 1,
            project_id: "project".into(),
            name: "Example".into(),
            prefix: "EX".into(),
            actors: vec![],
            stories: vec![json!({
                "id": "story",
                "title": "Attachment migration",
                "attachments": [{"id": "attachment", "archiveRelativePath": path}]
            })],
        };

        let mut sources = AttachmentSources::new();
        sources.insert(legacy_path.into(), source.to_string_lossy().into_owned());
        snapshot(legacy_path)
            .write_with_attachments(directory.path(), &sources)
            .unwrap();

        sources.clear();
        sources.insert(canonical_path.into(), source.to_string_lossy().into_owned());
        snapshot(canonical_path)
            .write_with_attachments(directory.path(), &sources)
            .unwrap();

        let root = directory.path().join(ARCHIVE_DIRECTORY);
        assert!(!root.join(legacy_path).exists());
        assert!(root.join(canonical_path).exists());
    }

    #[test]
    fn archive_recovers_from_a_nonempty_temporary_directory() {
        let directory = tempdir().unwrap();
        let temporary = directory.path().join(format!("{ARCHIVE_DIRECTORY}.tmp"));
        fs::create_dir_all(temporary.join("attachments/stale")).unwrap();
        fs::write(temporary.join("attachments/stale/file.bin"), b"stale").unwrap();
        let snapshot = ProjectSnapshot {
            format_version: 1,
            project_id: "project".into(),
            name: "Example".into(),
            prefix: "EX".into(),
            actors: vec![],
            stories: vec![],
        };

        snapshot.write(directory.path()).unwrap();

        assert!(!temporary.exists());
        assert!(
            directory
                .path()
                .join(ARCHIVE_DIRECTORY)
                .join("project.json")
                .is_file()
        );
    }

    #[test]
    fn legacy_archive_without_project_header_uses_known_project_identity() {
        let directory = tempdir().unwrap();
        let identity = ProjectSnapshot {
            format_version: 1,
            project_id: "project".into(),
            name: "Example".into(),
            prefix: "EX".into(),
            actors: vec![],
            stories: vec![],
        };
        identity.write(directory.path()).unwrap();
        fs::remove_file(
            directory
                .path()
                .join(ARCHIVE_DIRECTORY)
                .join("project.json"),
        )
        .unwrap();

        assert_eq!(
            ProjectSnapshot::read_legacy_with_identity(directory.path(), &identity).unwrap(),
            identity
        );
    }
}
