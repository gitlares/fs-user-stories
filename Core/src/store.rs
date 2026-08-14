// SPDX-License-Identifier: MIT

use std::path::Path;

use chrono::{DateTime, SecondsFormat, Utc};
use rusqlite::{Connection, OptionalExtension, params};

use crate::{
    protocol::CoreError,
    workspace::{
        WorkspaceAcceptanceCriterion, WorkspaceActor, WorkspaceAttachment,
        WorkspaceGitRepositoryLink, WorkspaceProject, WorkspaceStory,
    },
};

pub struct WorkspaceStore {
    connection: Connection,
}

impl WorkspaceStore {
    pub fn open(path: &Path) -> Result<Self, CoreError> {
        let connection = Connection::open(path)?;
        connection.execute_batch("PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL;")?;
        let store = Self { connection };
        store.migrate()?;
        Ok(store)
    }

    pub fn load_projects(&self) -> Result<Vec<WorkspaceProject>, CoreError> {
        let mut statement = self.connection.prepare(
            "SELECT id, name, prefix, git_local_path, git_remote_url, git_default_branch, \
             git_last_synced_digest, git_last_synced_at FROM projects ORDER BY position",
        )?;
        let projects = statement
            .query_map([], |row| {
                Ok(ProjectRow {
                    id: row.get(0)?,
                    name: row.get(1)?,
                    prefix: row.get(2)?,
                    local_path: row.get(3)?,
                    remote_url: row.get(4)?,
                    default_branch: row.get(5)?,
                    last_synced_digest: row.get(6)?,
                    last_synced_at: row.get(7)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?
            .into_iter()
            .map(|row| {
                let id = row.id.clone();
                Ok(WorkspaceProject {
                    id,
                    name: row.name,
                    prefix: row.prefix,
                    actors: self.load_actors(&row.id)?,
                    stories: self.load_stories(&row.id)?,
                    git_repository: row.local_path.map(|local_path| WorkspaceGitRepositoryLink {
                        local_path,
                        remote_url: row.remote_url,
                        default_branch: row
                            .default_branch
                            .unwrap_or_else(|| "fs-user-stories".into()),
                        last_synced_digest: row.last_synced_digest,
                        last_synced_at: row.last_synced_at.map(timestamp_to_rfc3339),
                    }),
                })
            })
            .collect::<Result<Vec<_>, CoreError>>()?;
        Ok(projects)
    }

    pub fn save_projects(&mut self, projects: &[WorkspaceProject]) -> Result<(), CoreError> {
        let transaction = self.connection.transaction()?;
        transaction.execute("DELETE FROM projects", [])?;
        for (position, project) in projects.iter().enumerate() {
            let last_synced_at = project
                .git_repository
                .as_ref()
                .and_then(|link| link.last_synced_at.as_deref())
                .map(rfc3339_to_timestamp)
                .transpose()?;
            transaction.execute(
                "INSERT INTO projects (id, name, prefix, position, git_local_path, git_remote_url, \
                 git_default_branch, git_last_synced_digest, git_last_synced_at) \
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                params![
                    project.id,
                    project.name,
                    project.prefix,
                    position as i64,
                    project.git_repository.as_ref().map(|link| &link.local_path),
                    project
                        .git_repository
                        .as_ref()
                        .and_then(|link| link.remote_url.as_deref()),
                    project
                        .git_repository
                        .as_ref()
                        .map(|link| &link.default_branch),
                    project
                        .git_repository
                        .as_ref()
                        .and_then(|link| link.last_synced_digest.as_deref()),
                    last_synced_at,
                ],
            )?;

            for (actor_position, actor) in project.actors.iter().enumerate() {
                transaction.execute(
                    "INSERT INTO actors (id, project_id, name, role, position) VALUES (?, ?, ?, ?, ?)",
                    params![actor.id, project.id, actor.name, actor.role, actor_position as i64],
                )?;
            }
            for story in &project.stories {
                transaction.execute(
                    "INSERT INTO stories (id, project_id, number, title, actor_id, want, outcome, status, \
                     notes, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    params![
                        story.id,
                        project.id,
                        story.number,
                        story.title,
                        story.actor_id,
                        story.want,
                        story.outcome,
                        story.status.as_str(),
                        story.notes,
                        rfc3339_to_timestamp(&story.created_at)?,
                    ],
                )?;
                for (criterion_position, criterion) in story.acceptance_criteria.iter().enumerate()
                {
                    transaction.execute(
                        "INSERT INTO acceptance_criteria (id, story_id, text, is_met, position) \
                         VALUES (?, ?, ?, ?, ?)",
                        params![
                            criterion.id,
                            story.id,
                            criterion.text,
                            i64::from(criterion.is_met),
                            criterion_position as i64,
                        ],
                    )?;
                }
                for (attachment_position, attachment) in story.attachments.iter().enumerate() {
                    transaction.execute(
                        "INSERT INTO attachments (id, story_id, filename, content_type, byte_size, sha256, \
                         relative_path, created_at, position) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        params![
                            attachment.id,
                            story.id,
                            attachment.filename,
                            attachment.content_type,
                            attachment.byte_size,
                            attachment.sha256,
                            attachment.relative_path,
                            rfc3339_to_timestamp(&attachment.created_at)?,
                            attachment_position as i64,
                        ],
                    )?;
                }
            }
        }
        transaction.commit()?;
        Ok(())
    }

    fn migrate(&self) -> Result<(), CoreError> {
        self.connection.execute_batch(
            "CREATE TABLE IF NOT EXISTS projects (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                prefix TEXT NOT NULL,
                position INTEGER NOT NULL,
                git_bookmark BLOB,
                git_display_path TEXT,
                git_remote_name TEXT,
                git_local_path TEXT,
                git_remote_url TEXT,
                git_default_branch TEXT,
                git_last_synced_digest TEXT,
                git_last_synced_at REAL
            );
            CREATE TABLE IF NOT EXISTS actors (
                id TEXT PRIMARY KEY NOT NULL,
                project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                role TEXT NOT NULL,
                position INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS stories (
                id TEXT PRIMARY KEY NOT NULL,
                project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                number INTEGER NOT NULL,
                title TEXT NOT NULL,
                actor_id TEXT NOT NULL,
                want TEXT NOT NULL,
                outcome TEXT NOT NULL,
                notes TEXT NOT NULL DEFAULT '',
                status TEXT NOT NULL,
                created_at REAL NOT NULL,
                UNIQUE(project_id, number)
            );
            CREATE TABLE IF NOT EXISTS acceptance_criteria (
                id TEXT PRIMARY KEY NOT NULL,
                story_id TEXT NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
                text TEXT NOT NULL,
                is_met INTEGER NOT NULL,
                position INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS attachments (
                id TEXT PRIMARY KEY NOT NULL,
                story_id TEXT NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
                filename TEXT NOT NULL,
                content_type TEXT NOT NULL,
                byte_size INTEGER NOT NULL,
                sha256 TEXT NOT NULL,
                relative_path TEXT NOT NULL,
                created_at REAL NOT NULL,
                position INTEGER NOT NULL
            );",
        )?;
        self.add_column_if_missing("stories", "notes", "TEXT NOT NULL DEFAULT ''")?;
        self.add_column_if_missing("projects", "git_bookmark", "BLOB")?;
        self.add_column_if_missing("projects", "git_display_path", "TEXT")?;
        self.add_column_if_missing("projects", "git_remote_name", "TEXT")?;
        self.add_column_if_missing("projects", "git_last_synced_digest", "TEXT")?;
        self.add_column_if_missing("projects", "git_last_synced_at", "REAL")?;
        self.add_column_if_missing("projects", "git_local_path", "TEXT")?;
        self.add_column_if_missing("projects", "git_remote_url", "TEXT")?;
        self.add_column_if_missing("projects", "git_default_branch", "TEXT")?;
        self.connection.pragma_update(None, "user_version", 5)?;
        Ok(())
    }

    fn add_column_if_missing(
        &self,
        table: &str,
        column: &str,
        definition: &str,
    ) -> Result<(), CoreError> {
        let found = self
            .connection
            .query_row(
                &format!("SELECT 1 FROM pragma_table_info('{table}') WHERE name = ? LIMIT 1"),
                [column],
                |_| Ok(()),
            )
            .optional()?
            .is_some();
        if !found {
            self.connection.execute(
                &format!("ALTER TABLE {table} ADD COLUMN {column} {definition}"),
                [],
            )?;
        }
        Ok(())
    }

    fn load_actors(&self, project_id: &str) -> Result<Vec<WorkspaceActor>, CoreError> {
        let mut statement = self
            .connection
            .prepare("SELECT id, name, role FROM actors WHERE project_id = ? ORDER BY position")?;
        Ok(statement
            .query_map([project_id], |row| {
                Ok(WorkspaceActor {
                    id: row.get(0)?,
                    name: row.get(1)?,
                    role: row.get(2)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?)
    }

    fn load_stories(&self, project_id: &str) -> Result<Vec<WorkspaceStory>, CoreError> {
        let mut statement = self.connection.prepare(
            "SELECT id, number, title, actor_id, want, outcome, status, notes, created_at \
             FROM stories WHERE project_id = ? ORDER BY number",
        )?;
        let rows = statement
            .query_map([project_id], |row| {
                Ok(StoryRow {
                    id: row.get(0)?,
                    number: row.get(1)?,
                    title: row.get(2)?,
                    actor_id: row.get(3)?,
                    want: row.get(4)?,
                    outcome: row.get(5)?,
                    status: row.get(6)?,
                    notes: row.get(7)?,
                    created_at: row.get(8)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;
        rows.into_iter()
            .map(|row| {
                Ok(WorkspaceStory {
                    acceptance_criteria: self.load_criteria(&row.id)?,
                    attachments: self.load_attachments(&row.id)?,
                    id: row.id,
                    number: row.number,
                    title: row.title,
                    actor_id: row.actor_id,
                    want: row.want,
                    outcome: row.outcome,
                    notes: row.notes,
                    status: serde_json::from_value(serde_json::Value::String(row.status))?,
                    created_at: timestamp_to_rfc3339(row.created_at),
                })
            })
            .collect()
    }

    fn load_criteria(
        &self,
        story_id: &str,
    ) -> Result<Vec<WorkspaceAcceptanceCriterion>, CoreError> {
        let mut statement = self.connection.prepare(
            "SELECT id, text, is_met FROM acceptance_criteria WHERE story_id = ? ORDER BY position",
        )?;
        Ok(statement
            .query_map([story_id], |row| {
                Ok(WorkspaceAcceptanceCriterion {
                    id: row.get(0)?,
                    text: row.get(1)?,
                    is_met: row.get::<_, i64>(2)? != 0,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?)
    }

    fn load_attachments(&self, story_id: &str) -> Result<Vec<WorkspaceAttachment>, CoreError> {
        let mut statement = self.connection.prepare(
            "SELECT id, filename, content_type, byte_size, sha256, relative_path, created_at \
             FROM attachments WHERE story_id = ? ORDER BY position",
        )?;
        Ok(statement
            .query_map([story_id], |row| {
                Ok(WorkspaceAttachment {
                    id: row.get(0)?,
                    filename: row.get(1)?,
                    content_type: row.get(2)?,
                    byte_size: row.get(3)?,
                    sha256: row.get(4)?,
                    relative_path: row.get(5)?,
                    created_at: timestamp_to_rfc3339(row.get(6)?),
                })
            })?
            .collect::<Result<Vec<_>, _>>()?)
    }
}

struct ProjectRow {
    id: String,
    name: String,
    prefix: String,
    local_path: Option<String>,
    remote_url: Option<String>,
    default_branch: Option<String>,
    last_synced_digest: Option<String>,
    last_synced_at: Option<f64>,
}

struct StoryRow {
    id: String,
    number: i64,
    title: String,
    actor_id: String,
    want: String,
    outcome: String,
    status: String,
    notes: String,
    created_at: f64,
}

fn timestamp_to_rfc3339(timestamp: f64) -> String {
    DateTime::<Utc>::from_timestamp(timestamp as i64, 0)
        .unwrap_or(DateTime::<Utc>::UNIX_EPOCH)
        .to_rfc3339_opts(SecondsFormat::Secs, true)
}

fn rfc3339_to_timestamp(value: &str) -> Result<f64, CoreError> {
    DateTime::parse_from_rfc3339(value)
        .map(|value| value.timestamp_millis() as f64 / 1_000.0)
        .map_err(|_| CoreError::InvalidWorkspaceDate(value.into()))
}

#[cfg(test)]
mod tests {
    use tempfile::tempdir;

    use super::*;
    use crate::workspace::{StoryStatus, WorkspaceAcceptanceCriterion};

    #[test]
    fn preserves_the_existing_sqlite_schema_and_story_data() {
        let directory = tempdir().expect("temporary directory");
        let path = directory.path().join("FSUserStories.sqlite3");
        let mut store = WorkspaceStore::open(&path).expect("store opens");
        let project = WorkspaceProject {
            id: "project".into(),
            name: "Project".into(),
            prefix: "PR".into(),
            actors: vec![],
            stories: vec![WorkspaceStory {
                id: "story".into(),
                number: 1,
                title: "Story".into(),
                actor_id: "actor".into(),
                want: "Need".into(),
                outcome: "Outcome".into(),
                notes: "Note".into(),
                acceptance_criteria: vec![WorkspaceAcceptanceCriterion {
                    id: "criterion".into(),
                    text: "Done".into(),
                    is_met: true,
                }],
                attachments: vec![],
                status: StoryStatus::Active,
                created_at: "2026-08-14T12:00:00Z".into(),
            }],
            git_repository: None,
        };
        store
            .save_projects(std::slice::from_ref(&project))
            .expect("project saves");
        assert_eq!(store.load_projects().expect("project loads"), vec![project]);
    }
}
