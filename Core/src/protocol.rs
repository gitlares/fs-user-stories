// SPDX-License-Identifier: MIT

use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use thiserror::Error;

use crate::{
    archive::{AttachmentSources, ProjectSnapshot},
    engine::RepositoryEngine,
    github::DeviceAuthorization,
    invitation::ProjectInvitation,
    markdown::{StoryMarkdownDocument, export_markdown, import_markdown},
    store::WorkspaceStore,
    sync::{ConflictResolution, MergeResult, apply_resolutions, merge_snapshots},
    sync_planner::{SyncPlannerRequest, plan},
    workspace::{
        WorkspaceCommand, WorkspaceProject, WorkspaceStoryQuery, apply_workspace_command,
        filter_stories,
    },
};

#[derive(Debug, Deserialize)]
#[serde(tag = "command", rename_all = "snake_case")]
pub enum Command {
    GithubBeginAuthorization {
        client_id: String,
    },
    GithubFinishAuthorization {
        client_id: String,
        authorization: DeviceAuthorization,
    },
    GithubCreatePrivateRepository {
        name: String,
        access_token: String,
    },
    GithubInviteCollaborator {
        username: String,
        repository_url: String,
        access_token: String,
    },
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
    #[serde(rename = "remote_uses_github", alias = "remote_uses_git_hub")]
    RemoteUsesGitHub {
        remote_url: String,
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
    ExportMarkdown {
        document: StoryMarkdownDocument,
    },
    ImportMarkdown {
        markdown: String,
    },
    ApplyWorkspaceCommand {
        project: WorkspaceProject,
        #[serde(flatten)]
        operation: WorkspaceCommand,
    },
    LoadWorkspace {
        database_path: PathBuf,
        #[serde(default)]
        attachments_root: Option<PathBuf>,
    },
    SearchWorkspace {
        database_path: PathBuf,
        query: WorkspaceStoryQuery,
    },
    PlanSynchronization {
        request: SyncPlannerRequest,
    },
    SynchronizeStoredProject {
        database_path: PathBuf,
        attachments_root: PathBuf,
        project_id: String,
        access_token: Option<String>,
    },
    InitializeStoredProjectRepository {
        database_path: PathBuf,
        attachments_root: PathBuf,
        project_id: String,
        repository_path: PathBuf,
    },
    ConnectStoredProjectRepository {
        database_path: PathBuf,
        attachments_root: PathBuf,
        project_id: String,
        remote_url: String,
    },
    ResolveStoredProjectSynchronization {
        database_path: PathBuf,
        attachments_root: PathBuf,
        project_id: String,
        resolutions: Vec<ConflictResolution>,
        access_token: Option<String>,
    },
    JoinStoredProject {
        database_path: PathBuf,
        attachments_root: PathBuf,
        repositories_root: PathBuf,
        remote_url: String,
        access_token: Option<String>,
    },
    ImportStoredAttachments {
        database_path: PathBuf,
        attachments_root: PathBuf,
        project_id: String,
        story_id: String,
        source_paths: Vec<PathBuf>,
    },
    RemoveStoredAttachment {
        database_path: PathBuf,
        attachments_root: PathBuf,
        project_id: String,
        story_id: String,
        attachment_id: String,
    },
    SaveWorkspace {
        database_path: PathBuf,
        projects: Vec<WorkspaceProject>,
    },
    CreateStoredProject {
        database_path: PathBuf,
        name: String,
        prefix: String,
    },
    DeleteStoredProject {
        database_path: PathBuf,
        attachments_root: PathBuf,
        repositories_root: PathBuf,
        project_id: String,
    },
    DeleteStoredStory {
        database_path: PathBuf,
        attachments_root: PathBuf,
        project_id: String,
        story_id: String,
    },
    ApplyStoredWorkspaceCommand {
        database_path: PathBuf,
        project_id: String,
        #[serde(flatten)]
        operation: WorkspaceCommand,
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
        Command::GithubBeginAuthorization { client_id } => {
            Response::success(crate::github::begin_authorization(&client_id)?)
        }
        Command::GithubFinishAuthorization {
            client_id,
            authorization,
        } => Response::success(json!({
            "accessToken": crate::github::finish_authorization(&client_id, &authorization)?
        })),
        Command::GithubCreatePrivateRepository { name, access_token } => Response::success(
            crate::github::create_private_repository(&name, &access_token)?,
        ),
        Command::GithubInviteCollaborator {
            username,
            repository_url,
            access_token,
        } => {
            crate::github::invite_collaborator(&username, &repository_url, &access_token)?;
            Response::success(json!({}))
        }
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
            let remote_url = RepositoryEngine::new(repository_path).connect(&remote_url)?;
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
        Command::RemoteUsesGitHub { remote_url } => Response::success(json!({
            "usesGitHub": crate::github::is_github_repository_url(&remote_url)
        })),
        Command::Merge {
            base,
            local,
            shared,
        } => Response::success(merge_snapshots(&base, &local, &shared)?),
        Command::Resolve {
            result,
            resolutions,
        } => Response::success(apply_resolutions(result, &resolutions)?),
        Command::ExportMarkdown { document } => {
            Response::success(json!({"markdown": export_markdown(&document)?}))
        }
        Command::ImportMarkdown { markdown } => Response::success(import_markdown(&markdown)?),
        Command::ApplyWorkspaceCommand { project, operation } => {
            Response::success(apply_workspace_command(project, operation)?)
        }
        Command::LoadWorkspace {
            database_path,
            attachments_root,
        } => {
            let mut store = WorkspaceStore::open(&database_path)?;
            let mut projects = store.load_projects()?;
            if let Some(attachments_root) = attachments_root {
                if crate::mcp_server::migrate_attachment_paths(&mut projects, &attachments_root)
                    .map_err(CoreError::StoredWorkspaceOperation)?
                {
                    store.save_projects(&projects)?;
                }
            }
            Response::success(json!({"projects": projects}))
        }
        Command::SearchWorkspace {
            database_path,
            query,
        } => {
            let projects = WorkspaceStore::open(&database_path)?.load_projects()?;
            Response::success(json!({"matches": filter_stories(&projects, &query)?}))
        }
        Command::PlanSynchronization { request } => Response::success(plan(request)),
        Command::SynchronizeStoredProject {
            database_path,
            attachments_root,
            project_id,
            access_token,
        } => Response::success(crate::mcp_server::synchronize_stored_project(
            database_path,
            attachments_root,
            project_id,
            access_token,
        )?),
        Command::InitializeStoredProjectRepository {
            database_path,
            attachments_root,
            project_id,
            repository_path,
        } => Response::success(crate::mcp_server::initialize_stored_project_repository(
            database_path,
            attachments_root,
            project_id,
            repository_path,
        )?),
        Command::ConnectStoredProjectRepository {
            database_path,
            attachments_root,
            project_id,
            remote_url,
        } => Response::success(crate::mcp_server::connect_stored_project_repository(
            database_path,
            attachments_root,
            project_id,
            remote_url,
        )?),
        Command::ResolveStoredProjectSynchronization {
            database_path,
            attachments_root,
            project_id,
            resolutions,
            access_token,
        } => Response::success(crate::mcp_server::resolve_stored_project_synchronization(
            database_path,
            attachments_root,
            project_id,
            resolutions,
            access_token,
        )?),
        Command::JoinStoredProject {
            database_path,
            attachments_root,
            repositories_root,
            remote_url,
            access_token,
        } => Response::success(crate::mcp_server::join_stored_project(
            database_path,
            attachments_root,
            repositories_root,
            remote_url,
            access_token,
        )?),
        Command::ImportStoredAttachments {
            database_path,
            attachments_root,
            project_id,
            story_id,
            source_paths,
        } => Response::success(crate::mcp_server::import_stored_attachments(
            database_path,
            attachments_root,
            project_id,
            story_id,
            source_paths,
        )?),
        Command::RemoveStoredAttachment {
            database_path,
            attachments_root,
            project_id,
            story_id,
            attachment_id,
        } => Response::success(crate::mcp_server::remove_stored_attachment(
            database_path,
            attachments_root,
            project_id,
            story_id,
            attachment_id,
        )?),
        Command::SaveWorkspace {
            database_path,
            projects,
        } => {
            WorkspaceStore::open(&database_path)?.save_projects(&projects)?;
            Response::success(json!({}))
        }
        Command::CreateStoredProject {
            database_path,
            name,
            prefix,
        } => {
            let mut store = WorkspaceStore::open(&database_path)?;
            let mut projects = store.load_projects()?;
            let project = apply_workspace_command(
                WorkspaceProject {
                    id: uuid::Uuid::new_v4().to_string().to_uppercase(),
                    name: String::new(),
                    prefix: String::new(),
                    actors: vec![],
                    stories: vec![],
                    git_repository: None,
                },
                WorkspaceCommand::UpdateProject { name, prefix },
            )?
            .project;
            projects.push(project.clone());
            store.save_projects(&projects)?;
            Response::success(json!({"project": project}))
        }
        Command::DeleteStoredProject {
            database_path,
            attachments_root,
            repositories_root,
            project_id,
        } => {
            let mut store = WorkspaceStore::open(&database_path)?;
            let mut projects = store.load_projects()?;
            let before = projects.len();
            projects.retain(|project| project.id != project_id);
            if projects.len() == before {
                return Err(CoreError::WorkspaceProjectNotFound);
            }
            store.save_projects(&projects)?;
            let attachment_directory = attachments_root.join(&project_id);
            if attachment_directory.exists() {
                std::fs::remove_dir_all(attachment_directory)?;
            }
            let repository_directory = repositories_root.join(&project_id);
            if repository_directory.exists() {
                std::fs::remove_dir_all(repository_directory)?;
            }
            Response::success(json!({}))
        }
        Command::DeleteStoredStory {
            database_path,
            attachments_root,
            project_id,
            story_id,
        } => {
            let mut store = WorkspaceStore::open(&database_path)?;
            let mut projects = store.load_projects()?;
            let project_index = projects
                .iter()
                .position(|project| project.id == project_id)
                .ok_or(CoreError::WorkspaceProjectNotFound)?;
            projects[project_index] = apply_workspace_command(
                projects[project_index].clone(),
                WorkspaceCommand::DeleteStory {
                    story_id: story_id.clone(),
                },
            )?
            .project;
            store.save_projects(&projects)?;
            let story_directory = attachments_root.join(project_id).join(story_id);
            if story_directory.exists() {
                std::fs::remove_dir_all(story_directory)?;
            }
            Response::success(json!({"project": projects[project_index]}))
        }
        Command::ApplyStoredWorkspaceCommand {
            database_path,
            project_id,
            operation,
        } => {
            let mut store = WorkspaceStore::open(&database_path)?;
            let mut projects = store.load_projects()?;
            let project_index = projects
                .iter()
                .position(|project| project.id == project_id)
                .ok_or(CoreError::WorkspaceProjectNotFound)?;
            let result = apply_workspace_command(projects[project_index].clone(), operation)?;
            projects[project_index] = result.project.clone();
            store.save_projects(&projects)?;
            Response::success(result)
        }
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
    #[error("{0}")]
    Sqlite(#[from] rusqlite::Error),
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
    #[error("Choose at least one story")]
    MarkdownNoStories,
    #[error("This Markdown document was not exported by FS User Stories")]
    UnsupportedMarkdown,
    #[error("The Markdown document contains an unreadable story")]
    InvalidMarkdownStory,
    #[error("The story could not be found")]
    WorkspaceStoryNotFound,
    #[error("The project could not be found")]
    WorkspaceProjectNotFound,
    #[error("The profile could not be found")]
    WorkspaceActorNotFound,
    #[error("A profile used by stories cannot be deleted")]
    WorkspaceActorInUse,
    #[error("A project name is required")]
    WorkspaceNameRequired,
    #[error("A project prefix is required")]
    WorkspacePrefixRequired,
    #[error("A story title is required")]
    WorkspaceStoryTitleRequired,
    #[error("The story need is required")]
    WorkspaceStoryWantRequired,
    #[error("The story outcome is required")]
    WorkspaceStoryOutcomeRequired,
    #[error("At least one attachment is required")]
    WorkspaceAttachmentsRequired,
    #[error("The attachment could not be found")]
    WorkspaceAttachmentNotFound,
    #[error("A story can have up to 10 attachments")]
    WorkspaceAttachmentLimit,
    #[error("Attachments for a story cannot exceed 50 MB")]
    WorkspaceAttachmentSizeLimit,
    #[error("The acceptance criterion could not be found")]
    WorkspaceCriterionNotFound,
    #[error("Completed stories are read-only. Change the status before editing.")]
    CompletedStoryReadOnly,
    #[error("Complete every acceptance criterion before marking this story as done")]
    IncompleteAcceptanceCriteria,
    #[error("Add an acceptance criterion")]
    AcceptanceCriterionRequired,
    #[error("Invalid workspace date: {0}")]
    InvalidWorkspaceDate(String),
    #[error("Invalid MCP server configuration: {0}")]
    InvalidMCPConfiguration(String),
    #[error("Stored workspace operation failed: {0}")]
    StoredWorkspaceOperation(String),
    #[error("The project changed locally while synchronization was running")]
    WorkspaceChangedDuringSync,
    #[error("GitHub repository creation is not configured in this build")]
    GitHubNotConfigured,
    #[error("GitHub returned an invalid response")]
    GitHubInvalidResponse,
    #[error("The GitHub authorization code expired. Try again.")]
    GitHubAuthorizationExpired,
    #[error("GitHub authorization was cancelled")]
    GitHubAuthorizationDenied,
    #[error("GitHub error: {0}")]
    GitHubApi(String),
}

impl CoreError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::Io(_) => "io_error",
            Self::Json(_) => "json_error",
            Self::Git(_) => "git_error",
            Self::Sqlite(_) => "sqlite_error",
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
            Self::MarkdownNoStories => "markdown_no_stories",
            Self::UnsupportedMarkdown => "unsupported_markdown",
            Self::InvalidMarkdownStory => "invalid_markdown_story",
            Self::WorkspaceStoryNotFound => "workspace_story_not_found",
            Self::WorkspaceProjectNotFound => "workspace_project_not_found",
            Self::WorkspaceActorNotFound => "workspace_actor_not_found",
            Self::WorkspaceActorInUse => "workspace_actor_in_use",
            Self::WorkspaceNameRequired => "workspace_name_required",
            Self::WorkspacePrefixRequired => "workspace_prefix_required",
            Self::WorkspaceStoryTitleRequired => "workspace_story_title_required",
            Self::WorkspaceStoryWantRequired => "workspace_story_want_required",
            Self::WorkspaceStoryOutcomeRequired => "workspace_story_outcome_required",
            Self::WorkspaceAttachmentsRequired => "workspace_attachments_required",
            Self::WorkspaceAttachmentNotFound => "workspace_attachment_not_found",
            Self::WorkspaceAttachmentLimit => "workspace_attachment_limit",
            Self::WorkspaceAttachmentSizeLimit => "workspace_attachment_size_limit",
            Self::WorkspaceCriterionNotFound => "workspace_criterion_not_found",
            Self::CompletedStoryReadOnly => "completed_story_read_only",
            Self::IncompleteAcceptanceCriteria => "incomplete_acceptance_criteria",
            Self::AcceptanceCriterionRequired => "acceptance_criterion_required",
            Self::InvalidWorkspaceDate(_) => "invalid_workspace_date",
            Self::InvalidMCPConfiguration(_) => "invalid_mcp_configuration",
            Self::StoredWorkspaceOperation(_) => "stored_workspace_operation",
            Self::WorkspaceChangedDuringSync => "workspace_changed_during_sync",
            Self::GitHubNotConfigured => "github_not_configured",
            Self::GitHubInvalidResponse => "github_invalid_response",
            Self::GitHubAuthorizationExpired => "github_authorization_expired",
            Self::GitHubAuthorizationDenied => "github_authorization_denied",
            Self::GitHubApi(_) => "github_api_error",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::Command;

    #[test]
    fn github_remote_command_accepts_canonical_and_legacy_names() {
        for command_name in ["remote_uses_github", "remote_uses_git_hub"] {
            let command: Command = serde_json::from_value(serde_json::json!({
                "command": command_name,
                "remote_url": "https://github.com/example/project.git"
            }))
            .expect("GitHub remote command should deserialize");

            assert!(matches!(command, Command::RemoteUsesGitHub { .. }));
        }
    }
}
