// SPDX-License-Identifier: MIT

use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use thiserror::Error;

use crate::{
    archive::{AttachmentSources, ProjectSnapshot},
    engine::RepositoryEngine,
    invitation::ProjectInvitation,
    sync::{ConflictResolution, MergeResult, apply_resolutions, merge_snapshots},
};

#[derive(Debug, Deserialize)]
#[serde(tag = "command", rename_all = "snake_case")]
pub enum Command {
    CreateRepository {
        repository_path: PathBuf,
        snapshot: ProjectSnapshot,
        #[serde(default)]
        attachment_sources: AttachmentSources,
    },
    ConnectRemote {
        repository_path: PathBuf,
        remote_url: String,
    },
    CloneShared {
        repository_path: PathBuf,
        remote_url: String,
        #[serde(default)]
        access_token: Option<String>,
    },
    Synchronize {
        repository_path: PathBuf,
        snapshot: ProjectSnapshot,
        #[serde(default)]
        attachment_sources: AttachmentSources,
        #[serde(default)]
        access_token: Option<String>,
    },
    ResolveSynchronization {
        repository_path: PathBuf,
        resolutions: Vec<ConflictResolution>,
        #[serde(default)]
        attachment_sources: AttachmentSources,
        #[serde(default)]
        access_token: Option<String>,
    },
    CreateInvitation {
        project_id: String,
        project_name: String,
        remote_url: String,
        #[serde(default = "default_branch")]
        default_branch: String,
    },
    ReadInvitation {
        invitation: String,
    },
    Merge {
        base: Box<ProjectSnapshot>,
        local: Box<ProjectSnapshot>,
        shared: Box<ProjectSnapshot>,
    },
    Resolve {
        result: MergeResult,
        resolutions: Vec<ConflictResolution>,
    },
}

fn default_branch() -> String {
    "fs-user-stories".into()
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Response {
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<ErrorPayload>,
}

#[derive(Debug, Serialize)]
pub struct ErrorPayload {
    pub code: String,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub details: Option<Value>,
}

impl Response {
    pub fn success(result: impl Serialize) -> Result<Self, CoreError> {
        Ok(Self {
            ok: true,
            result: Some(serde_json::to_value(result)?),
            error: None,
        })
    }

    pub fn error(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            ok: false,
            result: None,
            error: Some(ErrorPayload {
                code: code.into(),
                message: message.into(),
                details: None,
            }),
        }
    }

    pub fn from_error(error: CoreError) -> Self {
        let details = match &error {
            CoreError::SyncConflicts(value) => serde_json::from_str(value).ok(),
            _ => None,
        };
        Self {
            ok: false,
            result: None,
            error: Some(ErrorPayload {
                code: error.code().into(),
                message: error.to_string(),
                details,
            }),
        }
    }
}

pub fn execute(command: Command) -> Result<Response, CoreError> {
    match command {
        Command::CreateRepository {
            repository_path,
            snapshot,
            attachment_sources,
        } => {
            let digest =
                RepositoryEngine::new(repository_path).create(&snapshot, &attachment_sources)?;
            Response::success(json!({"digest": digest}))
        }
        Command::ConnectRemote {
            repository_path,
            remote_url,
        } => {
            RepositoryEngine::new(repository_path).connect(&remote_url)?;
            Response::success(json!({"remoteURL": remote_url}))
        }
        Command::CloneShared {
            repository_path,
            remote_url,
            access_token,
        } => {
            let snapshot = RepositoryEngine::clone_shared(
                &remote_url,
                &repository_path,
                access_token.as_deref(),
            )?;
            Response::success(snapshot)
        }
        Command::Synchronize {
            repository_path,
            snapshot,
            attachment_sources,
            access_token,
        } => Response::success(RepositoryEngine::new(repository_path).synchronize(
            &snapshot,
            &attachment_sources,
            access_token.as_deref(),
        )?),
        Command::ResolveSynchronization {
            repository_path,
            resolutions,
            attachment_sources,
            access_token,
        } => Response::success(
            RepositoryEngine::new(repository_path).resolve_synchronization(
                &resolutions,
                &attachment_sources,
                access_token.as_deref(),
            )?,
        ),
        Command::CreateInvitation {
            project_id,
            project_name,
            remote_url,
            default_branch,
        } => {
            let invitation =
                ProjectInvitation::new(project_id, project_name, remote_url, default_branch)?;
            Response::success(json!({"invitation": invitation.encode()?}))
        }
        Command::ReadInvitation { invitation } => {
            Response::success(ProjectInvitation::decode(&invitation)?)
        }
        Command::Merge {
            base,
            local,
            shared,
        } => Response::success(merge_snapshots(&base, &local, &shared)?),
        Command::Resolve {
            result,
            resolutions,
        } => Response::success(apply_resolutions(result, &resolutions)?),
    }
}

#[derive(Debug, Error)]
pub enum CoreError {
    #[error("{0}")]
    Io(#[from] std::io::Error),
    #[error("{0}")]
    Json(#[from] serde_json::Error),
    #[error("{0}")]
    Git(#[from] git2::Error),
    #[error("This repository does not contain an FS User Stories archive")]
    ArchiveNotFound,
    #[error("Archive version {0} is not supported")]
    UnsupportedArchive(u32),
    #[error("Invalid archive: {0}")]
    InvalidArchive(String),
    #[error("The repository archive belongs to a different project")]
    ProjectMismatch,
    #[error("Invalid repository URL: {0}")]
    InvalidRemote(String),
    #[error("Invalid invitation: {0}")]
    InvalidInvitation(String),
    #[error("The destination folder is not empty")]
    RepositoryNotEmpty,
    #[error("Shared changes conflict with local changes")]
    SyncConflict,
    #[error("Some shared changes need your decision: {0}")]
    SyncConflicts(String),
    #[error("There is no pending synchronization to resolve")]
    NoPendingSync,
    #[error("Refusing to publish from protected branch {0}")]
    ProtectedBranch(String),
    #[error("The managed repository has an invalid state")]
    InvalidRepositoryState,
    #[error("Conflict {0} has not been resolved")]
    UnresolvedConflict(String),
}

impl CoreError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::Io(_) => "io_error",
            Self::Json(_) => "json_error",
            Self::Git(_) => "git_error",
            Self::ArchiveNotFound => "archive_not_found",
            Self::UnsupportedArchive(_) => "unsupported_archive",
            Self::InvalidArchive(_) => "invalid_archive",
            Self::ProjectMismatch => "project_mismatch",
            Self::InvalidRemote(_) => "invalid_remote",
            Self::InvalidInvitation(_) => "invalid_invitation",
            Self::RepositoryNotEmpty => "repository_not_empty",
            Self::SyncConflict => "sync_conflict",
            Self::SyncConflicts(_) => "sync_conflicts",
            Self::NoPendingSync => "no_pending_sync",
            Self::ProtectedBranch(_) => "protected_branch",
            Self::InvalidRepositoryState => "invalid_repository_state",
            Self::UnresolvedConflict(_) => "unresolved_conflict",
        }
    }
}
