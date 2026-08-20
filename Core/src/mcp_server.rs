// SPDX-License-Identifier: MIT

//! Loopback-only MCP transport and tool host.
//!
//! This module deliberately lives in the Rust core.  The macOS application only
//! starts this executable; it does not parse MCP messages or implement tools.

use std::{
    fs,
    io::{Read, Write},
    net::{Ipv4Addr, SocketAddrV4, TcpStream},
    path::{Path, PathBuf},
    thread,
    time::Duration,
};

use chrono::Utc;
use serde_json::{Map, Value, json};
use sha2::{Digest, Sha256};
use tiny_http::{Header, Method, Response, Server, StatusCode};
use uuid::Uuid;

use crate::{
    archive::{AttachmentSources, ProjectSnapshot},
    engine::RepositoryEngine,
    invitation::ProjectInvitation,
    protocol::CoreError,
    store::WorkspaceStore,
    sync::ConflictResolution,
    workspace::{
        StoryStatus, WorkspaceAcceptanceCriterion, WorkspaceAttachment, WorkspaceCommand,
        WorkspaceGitRepositoryLink, WorkspaceProject, apply_workspace_command,
    },
};

const MAXIMUM_FILE_SIZE: u64 = 10 * 1_024 * 1_024;
const DEFAULT_PORT: u16 = 49_231;

pub struct MCPServerConfig {
    pub database_path: PathBuf,
    pub attachments_root: PathBuf,
    pub port: u16,
}

pub fn run_from_arguments(arguments: &[String]) -> Result<(), CoreError> {
    let mut values = arguments.iter().skip(1);
    let mut database_path = None;
    let mut attachments_root = None;
    let mut port = DEFAULT_PORT;
    while let Some(argument) = values.next() {
        match argument.as_str() {
            "--database-path" => database_path = values.next().map(PathBuf::from),
            "--attachments-root" => attachments_root = values.next().map(PathBuf::from),
            "--port" => {
                port = values
                    .next()
                    .and_then(|value| value.parse().ok())
                    .ok_or_else(|| {
                        CoreError::InvalidMCPConfiguration("--port must be a valid port".into())
                    })?;
            }
            unknown => {
                return Err(CoreError::InvalidMCPConfiguration(format!(
                    "Unknown MCP server argument: {unknown}"
                )));
            }
        }
    }
    let database_path = database_path
        .ok_or_else(|| CoreError::InvalidMCPConfiguration("--database-path is required".into()))?;
    let attachments_root = attachments_root.ok_or_else(|| {
        CoreError::InvalidMCPConfiguration("--attachments-root is required".into())
    })?;
    run(MCPServerConfig {
        database_path,
        attachments_root,
        port,
    })
}

pub fn run(config: MCPServerConfig) -> Result<(), CoreError> {
    fs::create_dir_all(&config.attachments_root)?;
    // Opening here validates/migrates the sole shared database before reporting ready.
    WorkspaceStore::open(&config.database_path)?;
    let server = bind_or_follow_existing_server(config.port)?;

    for mut request in server.incoming_requests() {
        if !is_trusted_origin(&request) {
            let _ = request.respond(empty_response(StatusCode(403)));
            continue;
        }
        let response = match (request.method(), request.url()) {
            (&Method::Post, "/mcp") => {
                let mut body = String::new();
                let response = match request.as_reader().read_to_string(&mut body) {
                    Ok(_) => handle_rpc(&body, &config),
                    Err(error) => rpc_error(Value::Null, -32700, &error.to_string()),
                };
                json_response(response, StatusCode(200))
            }
            (&Method::Get, path) if path.starts_with("/attachments/") => {
                attachment_response(path, &config)
            }
            (&Method::Get, "/health") => json_response(json!({"status": "ready"}), StatusCode(200)),
            _ => empty_response(StatusCode(404)),
        };
        let _ = request.respond(response);
    }
    Ok(())
}

fn bind_or_follow_existing_server(port: u16) -> Result<Server, CoreError> {
    loop {
        match Server::http(("127.0.0.1", port)) {
            Ok(server) => return Ok(server),
            Err(_error) if existing_fs_user_stories_server(port) => {
                // A previous app build is still alive in the menu bar. Keep this
                // process as a lightweight successor: the existing server remains
                // usable now, and this process takes over the fixed endpoint as
                // soon as the previous instance quits.
                thread::sleep(Duration::from_secs(1));
            }
            Err(error) => {
                return Err(CoreError::InvalidMCPConfiguration(format!(
                    "Port {port} could not be opened: {error}"
                )));
            }
        }
    }
}

fn existing_fs_user_stories_server(port: u16) -> bool {
    let address = SocketAddrV4::new(Ipv4Addr::LOCALHOST, port);
    let Ok(mut stream) = TcpStream::connect_timeout(&address.into(), Duration::from_millis(300))
    else {
        return false;
    };
    let _ = stream.set_read_timeout(Some(Duration::from_millis(500)));
    let _ = stream.set_write_timeout(Some(Duration::from_millis(500)));
    let body = r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"FS User Stories app","version":"1"}}}"#;
    let request = format!(
        "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    if stream.write_all(request.as_bytes()).is_err() {
        return false;
    }
    let mut response = String::new();
    if stream.read_to_string(&mut response).is_err() {
        return false;
    }
    response
        .split_once("\r\n\r\n")
        .and_then(|(_, body)| serde_json::from_str::<Value>(body).ok())
        .and_then(|value| value.pointer("/result/serverInfo/name").cloned())
        .and_then(|value| value.as_str().map(str::to_owned))
        .is_some_and(|name| name == "FS User Stories")
}

fn is_trusted_origin(request: &tiny_http::Request) -> bool {
    let Some(origin) = request
        .headers()
        .iter()
        .find(|header| header.field.equiv("Origin"))
    else {
        return true;
    };
    let origin = origin.value.as_str();
    origin.starts_with("http://127.0.0.1:") || origin.starts_with("http://localhost:")
}

fn handle_rpc(body: &str, config: &MCPServerConfig) -> Value {
    let request = match serde_json::from_str::<Value>(body) {
        Ok(Value::Object(value)) => value,
        _ => return rpc_error(Value::Null, -32700, "Invalid JSON-RPC request"),
    };
    let id = request.get("id").cloned().unwrap_or(Value::Null);
    let Some(method) = request.get("method").and_then(Value::as_str) else {
        return rpc_error(id, -32600, "A method is required");
    };
    let params = request.get("params").and_then(Value::as_object);
    match method {
        "initialize" => rpc_success(
            id,
            json!({
                "protocolVersion": compatible_protocol(params),
                "capabilities": { "tools": { "listChanged": false }, "prompts": { "listChanged": false } },
                "serverInfo": { "name": "FS User Stories", "version": env!("CARGO_PKG_VERSION") },
                "instructions": "FS User Stories is local-first. Its Rust core owns the SQLite workspace and this loopback MCP server. Completed stories are read-only until reopened. Destructive tools require confirm=true."
            }),
        ),
        "ping" => rpc_success(id, json!({})),
        "tools/list" => rpc_success(id, json!({"tools": tool_definitions()})),
        "tools/call" => handle_tool_call(id, params, config),
        "prompts/list" => rpc_success(id, json!({"prompts": prompt_definitions()})),
        "prompts/get" => handle_prompt_get(id, params, config),
        _ => rpc_error(id, -32601, "Method not found"),
    }
}

fn compatible_protocol(params: Option<&Map<String, Value>>) -> &'static str {
    match params
        .and_then(|value| value.get("protocolVersion"))
        .and_then(Value::as_str)
    {
        Some("2025-03-26") => "2025-03-26",
        Some("2024-11-05") => "2024-11-05",
        _ => "2025-06-18",
    }
}

fn handle_tool_call(
    id: Value,
    params: Option<&Map<String, Value>>,
    config: &MCPServerConfig,
) -> Value {
    let Some(name) = params
        .and_then(|value| value.get("name"))
        .and_then(Value::as_str)
    else {
        return rpc_error(id, -32602, "Tool name is required");
    };
    let arguments = params
        .and_then(|value| value.get("arguments"))
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    match execute_tool(name, &arguments, config) {
        Ok(value) => rpc_success(id, tool_result(value, false)),
        Err(error) => rpc_success(id, tool_result(json!({"error": error}), true)),
    }
}

fn execute_tool(
    name: &str,
    arguments: &Map<String, Value>,
    config: &MCPServerConfig,
) -> Result<Value, String> {
    match name {
        "about_app" => Ok(json!({
            "name": "FS User Stories",
            "version": env!("CARGO_PKG_VERSION"),
            "description": "A local-first workspace for clear user stories. The Rust core owns the local SQLite database and MCP tools.",
            "source_of_truth": "Local SQLite database",
            "mcp_url": format!("http://127.0.0.1:{}/mcp", config.port),
            "destructive_tools_require_confirmation": true
        })),
        "list_projects" => Ok(json!({"projects": load_projects(config)?})),
        "create_project" => {
            let project = create_project(
                required(arguments, "name")?,
                required(arguments, "prefix")?,
                config,
            )?;
            Ok(json!({"project": project}))
        }
        "update_project" => {
            let project_id = required(arguments, "project_id")?;
            let current = project(config, project_id)?;
            mutate(
                config,
                project_id,
                WorkspaceCommand::UpdateProject {
                    name: optional_or(arguments, "name", &current.name),
                    prefix: optional_or(arguments, "prefix", &current.prefix),
                },
            )
        }
        "delete_project" => {
            confirm(arguments)?;
            delete_project(config, required(arguments, "project_id")?)?;
            Ok(json!({"deleted": true}))
        }
        "get_project" => {
            let project = project(config, required(arguments, "project_id")?)?;
            Ok(json!({"project": project, "stories": project.stories}))
        }
        "get_repository_status" => {
            let project = project(config, required(arguments, "project_id")?)?;
            Ok(json!({"project_id": project.id, "repository": project.git_repository}))
        }
        "list_actors" => {
            let project = project(config, required(arguments, "project_id")?)?;
            Ok(json!({"actors": project.actors}))
        }
        "create_actor" => mutate(
            config,
            required(arguments, "project_id")?,
            WorkspaceCommand::AddActor {
                name: required(arguments, "name")?.into(),
                role: optional(arguments, "role"),
            },
        ),
        "update_actor" => {
            let project_id = required(arguments, "project_id")?;
            let existing = project(config, project_id)?;
            let actor_id = required(arguments, "actor_id")?;
            let actor = existing
                .actors
                .iter()
                .find(|actor| actor.id == actor_id)
                .ok_or("Actor not found")?;
            mutate(
                config,
                project_id,
                WorkspaceCommand::UpdateActor {
                    actor_id: actor_id.into(),
                    name: optional_or(arguments, "name", &actor.name),
                    role: optional_or(arguments, "role", &actor.role),
                },
            )
        }
        "delete_actor" => {
            confirm(arguments)?;
            mutate(
                config,
                required(arguments, "project_id")?,
                WorkspaceCommand::DeleteActor {
                    actor_id: required(arguments, "actor_id")?.into(),
                },
            )
        }
        "list_stories" => list_stories(arguments, config),
        "get_story" => {
            let project = project(config, required(arguments, "project_id")?)?;
            let story = project
                .stories
                .iter()
                .find(|story| story.id == required(arguments, "story_id").unwrap_or_default())
                .ok_or("Story not found")?;
            Ok(
                json!({"story": story, "project": {"id": project.id, "name": project.name, "prefix": project.prefix}}),
            )
        }
        "create_story" => mutate(
            config,
            required(arguments, "project_id")?,
            WorkspaceCommand::AddStory {
                title: required(arguments, "title")?.into(),
                actor_id: required(arguments, "actor_id")?.into(),
                want: required(arguments, "want")?.into(),
                outcome: required(arguments, "outcome")?.into(),
                acceptance_criteria: criteria_from(arguments)?,
            },
        ),
        "update_story" => update_story(arguments, config),
        "duplicate_story" => {
            let project_id = required(arguments, "project_id")?;
            let source = project(config, project_id)?
                .stories
                .into_iter()
                .find(|story| story.id == required(arguments, "story_id").unwrap_or_default())
                .ok_or("Story not found")?;
            mutate(
                config,
                project_id,
                WorkspaceCommand::DuplicateStory {
                    story_id: source.id,
                    copy_title: optional_or(arguments, "title", &format!("{} Copy", source.title)),
                },
            )
        }
        "delete_story" => {
            confirm(arguments)?;
            mutate(
                config,
                required(arguments, "project_id")?,
                WorkspaceCommand::DeleteStory {
                    story_id: required(arguments, "story_id")?.into(),
                },
            )
        }
        "add_acceptance_criterion" => mutate(
            config,
            required(arguments, "project_id")?,
            WorkspaceCommand::AddAcceptanceCriterion {
                story_id: required(arguments, "story_id")?.into(),
                text: required(arguments, "text")?.into(),
            },
        ),
        "set_acceptance_criterion" => mutate(
            config,
            required(arguments, "project_id")?,
            WorkspaceCommand::SetAcceptanceCriterion {
                story_id: required(arguments, "story_id")?.into(),
                criterion_id: required(arguments, "criterion_id")?.into(),
                is_met: arguments
                    .get("is_met")
                    .and_then(Value::as_bool)
                    .ok_or("is_met must be true or false")?,
            },
        ),
        "delete_acceptance_criterion" => {
            confirm(arguments)?;
            mutate(
                config,
                required(arguments, "project_id")?,
                WorkspaceCommand::DeleteAcceptanceCriterion {
                    story_id: required(arguments, "story_id")?.into(),
                    criterion_id: required(arguments, "criterion_id")?.into(),
                },
            )
        }
        "set_story_status" => mutate(
            config,
            required(arguments, "project_id")?,
            WorkspaceCommand::SetStoryStatus {
                story_id: required(arguments, "story_id")?.into(),
                status: status(required(arguments, "status")?)?,
            },
        ),
        "update_notes" => mutate(
            config,
            required(arguments, "project_id")?,
            WorkspaceCommand::UpdateStoryNotes {
                story_id: required(arguments, "story_id")?.into(),
                notes: required(arguments, "notes")?.into(),
            },
        ),
        "list_attachments" => attachments(arguments, config),
        "add_attachments" => add_attachments(arguments, config),
        "get_attachment" => attachment(arguments, config),
        "delete_attachment" => delete_attachment(arguments, config),
        "connect_shared_repository" => connect_shared_repository(arguments, config),
        "synchronize_project" => synchronize_project(arguments, config),
        "create_share_invitation" => create_share_invitation(arguments, config),
        _ => Err(format!("Unknown tool: {name}")),
    }
}

fn load_projects(config: &MCPServerConfig) -> Result<Vec<WorkspaceProject>, String> {
    WorkspaceStore::open(&config.database_path)
        .and_then(|store| store.load_projects())
        .map_err(|error| error.to_string())
}

fn project(config: &MCPServerConfig, id: &str) -> Result<WorkspaceProject, String> {
    load_projects(config)?
        .into_iter()
        .find(|project| project.id == id)
        .ok_or_else(|| "Project not found".into())
}

fn create_project(
    name: &str,
    prefix: &str,
    config: &MCPServerConfig,
) -> Result<WorkspaceProject, String> {
    let mut store =
        WorkspaceStore::open(&config.database_path).map_err(|error| error.to_string())?;
    let mut projects = store.load_projects().map_err(|error| error.to_string())?;
    let project = apply_workspace_command(
        WorkspaceProject {
            id: Uuid::new_v4().to_string().to_uppercase(),
            name: String::new(),
            prefix: String::new(),
            actors: vec![],
            stories: vec![],
            git_repository: None,
        },
        WorkspaceCommand::UpdateProject {
            name: name.into(),
            prefix: prefix.into(),
        },
    )
    .map_err(|error| error.to_string())?
    .project;
    projects.push(project.clone());
    store
        .save_projects(&projects)
        .map_err(|error| error.to_string())?;
    Ok(project)
}

fn delete_project(config: &MCPServerConfig, project_id: &str) -> Result<(), String> {
    let mut store =
        WorkspaceStore::open(&config.database_path).map_err(|error| error.to_string())?;
    let mut projects = store.load_projects().map_err(|error| error.to_string())?;
    let before = projects.len();
    projects.retain(|project| project.id != project_id);
    if projects.len() == before {
        return Err("Project not found".into());
    }
    store
        .save_projects(&projects)
        .map_err(|error| error.to_string())
}

fn save_updated_project(config: &MCPServerConfig, updated: WorkspaceProject) -> Result<(), String> {
    let mut store =
        WorkspaceStore::open(&config.database_path).map_err(|error| error.to_string())?;
    let mut projects = store.load_projects().map_err(|error| error.to_string())?;
    let index = projects
        .iter()
        .position(|project| project.id == updated.id)
        .ok_or("Project not found")?;
    projects[index] = updated;
    store
        .save_projects(&projects)
        .map_err(|error| error.to_string())
}

fn connect_shared_repository(
    arguments: &Map<String, Value>,
    config: &MCPServerConfig,
) -> Result<Value, String> {
    let mut project = project(config, required(arguments, "project_id")?)?;
    let remote_url = required(arguments, "remote_url")?;
    let link = project
        .git_repository
        .as_mut()
        .ok_or("The managed local repository is not ready")?;
    let remote_url = RepositoryEngine::new(&link.local_path)
        .connect(remote_url)
        .map_err(|error| error.to_string())?;
    link.remote_url = Some(remote_url);
    save_updated_project(config, project.clone())?;
    Ok(json!({"project": project}))
}

fn create_share_invitation(
    arguments: &Map<String, Value>,
    config: &MCPServerConfig,
) -> Result<Value, String> {
    let project = project(config, required(arguments, "project_id")?)?;
    let link = project
        .git_repository
        .as_ref()
        .ok_or("The managed local repository is not ready")?;
    let remote_url = link
        .remote_url
        .as_deref()
        .ok_or("Connect a shared repository first")?;
    let invitation = ProjectInvitation::new(
        project.id,
        project.name,
        remote_url.into(),
        link.default_branch.clone(),
    )
    .map_err(|error| error.to_string())?;
    Ok(json!({"invitation": invitation.encode().map_err(|error| error.to_string())?}))
}

fn synchronize_project(
    arguments: &Map<String, Value>,
    config: &MCPServerConfig,
) -> Result<Value, String> {
    confirm(arguments)?;
    let project = project(config, required(arguments, "project_id")?)?;
    let link = project
        .git_repository
        .as_ref()
        .ok_or("The managed local repository is not ready")?;
    if link.remote_url.is_none() {
        return Err("Connect a shared repository first".into());
    }
    let snapshot = project_snapshot(&project)?;
    let sources = attachment_sources(&project, config);
    let outcome = RepositoryEngine::new(&link.local_path)
        .synchronize(&snapshot, &sources, None)
        .map_err(|error| error.to_string())?;
    let mut synchronized = workspace_project_from_snapshot(outcome.snapshot, &project, config)?;
    let mut synchronized_link = link.clone();
    synchronized_link.last_synced_digest = Some(outcome.digest.clone());
    synchronized_link.last_synced_at = Some(Utc::now().to_rfc3339());
    synchronized.git_repository = Some(synchronized_link);
    save_updated_project(config, synchronized.clone())?;
    Ok(json!({"project": synchronized, "digest": outcome.digest}))
}

pub fn synchronize_stored_project(
    database_path: PathBuf,
    attachments_root: PathBuf,
    project_id: String,
    access_token: Option<String>,
) -> Result<Value, CoreError> {
    let config = MCPServerConfig {
        database_path,
        attachments_root,
        port: DEFAULT_PORT,
    };
    let initial_project =
        project(&config, &project_id).map_err(CoreError::StoredWorkspaceOperation)?;
    let link = initial_project.git_repository.as_ref().ok_or_else(|| {
        CoreError::StoredWorkspaceOperation("The managed local repository is not ready".into())
    })?;
    let snapshot =
        project_snapshot(&initial_project).map_err(CoreError::StoredWorkspaceOperation)?;
    let outcome = RepositoryEngine::new(&link.local_path).synchronize(
        &snapshot,
        &attachment_sources(&initial_project, &config),
        access_token.as_deref(),
    )?;
    let mut synchronized =
        workspace_project_from_snapshot(outcome.snapshot, &initial_project, &config)
            .map_err(CoreError::StoredWorkspaceOperation)?;
    let mut synchronized_link = link.clone();
    synchronized_link.last_synced_digest = Some(outcome.digest.clone());
    synchronized_link.last_synced_at = Some(Utc::now().to_rfc3339());
    synchronized.git_repository = Some(synchronized_link);
    let current = project(&config, &project_id).map_err(CoreError::StoredWorkspaceOperation)?;
    ensure_workspace_unchanged(&initial_project, &current)?;
    save_updated_project(&config, synchronized.clone())
        .map_err(CoreError::StoredWorkspaceOperation)?;
    Ok(json!({"project": synchronized, "digest": outcome.digest}))
}

pub fn initialize_stored_project_repository(
    database_path: PathBuf,
    attachments_root: PathBuf,
    project_id: String,
    repository_path: PathBuf,
) -> Result<Value, CoreError> {
    let config = MCPServerConfig {
        database_path,
        attachments_root,
        port: DEFAULT_PORT,
    };
    let initial = project(&config, &project_id).map_err(CoreError::StoredWorkspaceOperation)?;
    if initial.git_repository.is_some() {
        return Ok(json!({"project": initial}));
    }
    let snapshot = project_snapshot(&initial).map_err(CoreError::StoredWorkspaceOperation)?;
    let digest = RepositoryEngine::new(&repository_path)
        .create(&snapshot, &attachment_sources(&initial, &config))?;
    let mut updated = initial.clone();
    updated.git_repository = Some(WorkspaceGitRepositoryLink {
        local_path: repository_path.to_string_lossy().into_owned(),
        remote_url: None,
        default_branch: "fs-user-stories".into(),
        last_synced_digest: Some(digest),
        last_synced_at: None,
    });
    let current = project(&config, &project_id).map_err(CoreError::StoredWorkspaceOperation)?;
    ensure_workspace_unchanged(&initial, &current)?;
    save_updated_project(&config, updated.clone()).map_err(CoreError::StoredWorkspaceOperation)?;
    Ok(json!({"project": updated}))
}

pub fn connect_stored_project_repository(
    database_path: PathBuf,
    attachments_root: PathBuf,
    project_id: String,
    remote_url: String,
) -> Result<Value, CoreError> {
    let config = MCPServerConfig {
        database_path,
        attachments_root,
        port: DEFAULT_PORT,
    };
    let initial = project(&config, &project_id).map_err(CoreError::StoredWorkspaceOperation)?;
    let mut updated = initial.clone();
    let link = updated.git_repository.as_mut().ok_or_else(|| {
        CoreError::StoredWorkspaceOperation("The managed local repository is not ready".into())
    })?;
    let remote_url = RepositoryEngine::new(&link.local_path).connect(&remote_url)?;
    link.remote_url = Some(remote_url);
    let current = project(&config, &project_id).map_err(CoreError::StoredWorkspaceOperation)?;
    ensure_workspace_unchanged(&initial, &current)?;
    save_updated_project(&config, updated.clone()).map_err(CoreError::StoredWorkspaceOperation)?;
    Ok(json!({"project": updated}))
}

pub fn resolve_stored_project_synchronization(
    database_path: PathBuf,
    attachments_root: PathBuf,
    project_id: String,
    resolutions: Vec<ConflictResolution>,
    access_token: Option<String>,
) -> Result<Value, CoreError> {
    let config = MCPServerConfig {
        database_path,
        attachments_root,
        port: DEFAULT_PORT,
    };
    let initial = project(&config, &project_id).map_err(CoreError::StoredWorkspaceOperation)?;
    let link = initial.git_repository.as_ref().ok_or_else(|| {
        CoreError::StoredWorkspaceOperation("The managed local repository is not ready".into())
    })?;
    let outcome = RepositoryEngine::new(&link.local_path).resolve_synchronization(
        &resolutions,
        &attachment_sources(&initial, &config),
        access_token.as_deref(),
    )?;
    let mut updated = workspace_project_from_snapshot(outcome.snapshot, &initial, &config)
        .map_err(CoreError::StoredWorkspaceOperation)?;
    let mut updated_link = link.clone();
    updated_link.last_synced_digest = Some(outcome.digest.clone());
    updated_link.last_synced_at = Some(Utc::now().to_rfc3339());
    updated.git_repository = Some(updated_link);
    let current = project(&config, &project_id).map_err(CoreError::StoredWorkspaceOperation)?;
    ensure_workspace_unchanged(&initial, &current)?;
    save_updated_project(&config, updated.clone()).map_err(CoreError::StoredWorkspaceOperation)?;
    Ok(json!({"project": updated, "digest": outcome.digest}))
}

pub fn join_stored_project(
    database_path: PathBuf,
    attachments_root: PathBuf,
    repositories_root: PathBuf,
    remote_url: String,
    access_token: Option<String>,
) -> Result<Value, CoreError> {
    let remote_url = crate::invitation::normalize_remote_url(&remote_url)?;
    fs::create_dir_all(&repositories_root)?;
    let import_id = Uuid::new_v4().simple().to_string();
    let temporary_path = repositories_root.join(format!("i-{}", &import_id[..12]));
    let snapshot =
        match RepositoryEngine::clone_shared(&remote_url, &temporary_path, access_token.as_deref())
        {
            Ok(snapshot) => snapshot,
            Err(error) => {
                let _ = fs::remove_dir_all(&temporary_path);
                return Err(error);
            }
        };
    let final_path = repositories_root.join(repository_directory_name(&snapshot.project_id));
    let config = MCPServerConfig {
        database_path,
        attachments_root,
        port: DEFAULT_PORT,
    };
    let mut store = WorkspaceStore::open(&config.database_path)?;
    let mut projects = store.load_projects()?;
    if projects
        .iter()
        .any(|project| project.id == snapshot.project_id)
        || final_path.exists()
    {
        let _ = fs::remove_dir_all(&temporary_path);
        return Err(CoreError::StoredWorkspaceOperation(
            "This shared project is already on this computer".into(),
        ));
    }
    fs::rename(&temporary_path, &final_path)?;
    let digest = snapshot.digest()?;
    let seed = WorkspaceProject {
        id: snapshot.project_id.clone(),
        name: snapshot.name.clone(),
        prefix: snapshot.prefix.clone(),
        actors: vec![],
        stories: vec![],
        git_repository: Some(WorkspaceGitRepositoryLink {
            local_path: final_path.to_string_lossy().into_owned(),
            remote_url: Some(remote_url),
            default_branch: "fs-user-stories".into(),
            last_synced_digest: Some(digest),
            last_synced_at: Some(Utc::now().to_rfc3339()),
        }),
    };
    let imported = match workspace_project_from_snapshot(snapshot, &seed, &config) {
        Ok(project) => project,
        Err(error) => {
            let _ = fs::remove_dir_all(&final_path);
            return Err(CoreError::StoredWorkspaceOperation(error));
        }
    };
    projects.push(imported.clone());
    if let Err(error) = store.save_projects(&projects) {
        let _ = fs::remove_dir_all(&final_path);
        return Err(error);
    }
    Ok(json!({"project": imported}))
}

pub fn import_stored_attachments(
    database_path: PathBuf,
    attachments_root: PathBuf,
    project_id: String,
    story_id: String,
    source_paths: Vec<PathBuf>,
) -> Result<Value, CoreError> {
    if source_paths.is_empty() {
        return Err(CoreError::WorkspaceAttachmentsRequired);
    }
    let config = MCPServerConfig {
        database_path,
        attachments_root,
        port: DEFAULT_PORT,
    };
    let initial = project(&config, &project_id).map_err(CoreError::StoredWorkspaceOperation)?;
    let mut attachments = Vec::with_capacity(source_paths.len());
    let mut created_paths = Vec::with_capacity(source_paths.len());
    for source in source_paths {
        let metadata = fs::metadata(&source)?;
        let filename = source
            .file_name()
            .and_then(|value| value.to_str())
            .ok_or_else(|| CoreError::InvalidArchive("Invalid attachment filename".into()))?
            .to_owned();
        if !metadata.is_file() {
            return Err(CoreError::InvalidArchive(format!(
                "{filename} is not a file"
            )));
        }
        if metadata.len() > MAXIMUM_FILE_SIZE {
            return Err(CoreError::InvalidArchive(format!(
                "{filename} is larger than 10 MB"
            )));
        }
        let id = Uuid::new_v4().to_string().to_uppercase();
        let relative_path = managed_attachment_path(&project_id, &story_id, &id, &filename);
        let destination = config.attachments_root.join(&relative_path);
        fs::create_dir_all(
            destination.parent().ok_or_else(|| {
                CoreError::InvalidArchive("Invalid managed attachment path".into())
            })?,
        )?;
        fs::copy(&source, &destination)?;
        created_paths.push(destination);
        attachments.push(WorkspaceAttachment {
            id,
            filename: filename.clone(),
            content_type: attachment_content_type(&filename).into(),
            byte_size: metadata.len() as i64,
            sha256: file_sha256(&source)?,
            relative_path,
            created_at: Utc::now().to_rfc3339(),
        });
    }
    let result = apply_workspace_command(
        initial,
        WorkspaceCommand::AddAttachments {
            story_id: story_id.clone(),
            attachments,
        },
    );
    let updated = match result {
        Ok(result) => result.project,
        Err(error) => {
            for path in created_paths {
                let _ = fs::remove_file(path);
            }
            return Err(error);
        }
    };
    if let Err(error) = save_updated_project(&config, updated.clone()) {
        for path in created_paths {
            let _ = fs::remove_file(path);
        }
        return Err(CoreError::StoredWorkspaceOperation(error));
    }
    Ok(json!({"project": updated}))
}

pub fn remove_stored_attachment(
    database_path: PathBuf,
    attachments_root: PathBuf,
    project_id: String,
    story_id: String,
    attachment_id: String,
) -> Result<Value, CoreError> {
    let config = MCPServerConfig {
        database_path,
        attachments_root,
        port: DEFAULT_PORT,
    };
    let initial = project(&config, &project_id).map_err(CoreError::StoredWorkspaceOperation)?;
    let relative_path = initial
        .stories
        .iter()
        .find(|story| story.id == story_id)
        .and_then(|story| {
            story
                .attachments
                .iter()
                .find(|attachment| attachment.id == attachment_id)
        })
        .map(|attachment| attachment.relative_path.clone())
        .ok_or(CoreError::WorkspaceAttachmentNotFound)?;
    let updated = apply_workspace_command(
        initial,
        WorkspaceCommand::RemoveAttachment {
            story_id,
            attachment_id,
        },
    )?
    .project;
    save_updated_project(&config, updated.clone()).map_err(CoreError::StoredWorkspaceOperation)?;
    let path = config.attachments_root.join(relative_path);
    if path.exists() {
        fs::remove_file(path)?;
    }
    Ok(json!({"project": updated}))
}

fn file_sha256(path: &Path) -> Result<String, CoreError> {
    let mut file = fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; 64 * 1_024];
    loop {
        let count = file.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        hasher.update(&buffer[..count]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

fn attachment_content_type(filename: &str) -> &'static str {
    match Path::new(filename)
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase()
        .as_str()
    {
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "pdf" => "application/pdf",
        "txt" | "md" => "text/plain",
        "json" => "application/json",
        "csv" => "text/csv",
        _ => "application/octet-stream",
    }
}

fn ensure_workspace_unchanged(
    initial: &WorkspaceProject,
    current: &WorkspaceProject,
) -> Result<(), CoreError> {
    if initial == current {
        Ok(())
    } else {
        Err(CoreError::WorkspaceChangedDuringSync)
    }
}

fn project_snapshot(project: &WorkspaceProject) -> Result<ProjectSnapshot, String> {
    let actors = project
        .actors
        .iter()
        .map(|actor| serde_json::to_value(actor).map_err(|error| error.to_string()))
        .collect::<Result<Vec<_>, _>>()?;
    let stories = project
        .stories
        .iter()
        .map(|story| {
            let mut value = serde_json::to_value(story).map_err(|error| error.to_string())?;
            let attachments = value
                .get_mut("attachments")
                .and_then(Value::as_array_mut)
                .ok_or("Invalid story attachment data")?;
            for attachment in attachments {
                let object = attachment
                    .as_object_mut()
                    .ok_or("Invalid attachment data")?;
                let id = object
                    .get("id")
                    .and_then(Value::as_str)
                    .ok_or("Invalid attachment ID")?
                    .to_owned();
                let filename = object
                    .get("filename")
                    .and_then(Value::as_str)
                    .ok_or("Invalid attachment filename")?
                    .to_owned();
                object.remove("relativePath");
                object.insert(
                    "archiveRelativePath".into(),
                    Value::String(archive_attachment_path(&story.id, &id, &filename)),
                );
            }
            Ok(value)
        })
        .collect::<Result<Vec<_>, String>>()?;
    Ok(ProjectSnapshot {
        format_version: ProjectSnapshot::FORMAT_VERSION,
        project_id: project.id.clone(),
        name: project.name.clone(),
        prefix: project.prefix.clone(),
        actors,
        stories,
    })
}

fn attachment_sources(project: &WorkspaceProject, config: &MCPServerConfig) -> AttachmentSources {
    project
        .stories
        .iter()
        .flat_map(|story| {
            story.attachments.iter().map(move |attachment| {
                (
                    archive_attachment_path(&story.id, &attachment.id, &attachment.filename),
                    config
                        .attachments_root
                        .join(&attachment.relative_path)
                        .to_string_lossy()
                        .into_owned(),
                )
            })
        })
        .collect()
}

fn workspace_project_from_snapshot(
    snapshot: ProjectSnapshot,
    previous: &WorkspaceProject,
    config: &MCPServerConfig,
) -> Result<WorkspaceProject, String> {
    if snapshot.project_id != previous.id {
        return Err("The shared archive belongs to a different project".into());
    }
    let actors = snapshot
        .actors
        .into_iter()
        .map(|value| serde_json::from_value(value).map_err(|error| error.to_string()))
        .collect::<Result<Vec<_>, _>>()?;
    let stories = snapshot
        .stories
        .into_iter()
        .map(|mut value| {
            let story_id = value
                .get("id")
                .and_then(Value::as_str)
                .ok_or("Invalid shared story ID")?
                .to_owned();
            let attachments = value
                .get_mut("attachments")
                .and_then(Value::as_array_mut)
                .ok_or("Invalid shared story attachments")?;
            for attachment in attachments {
                let object = attachment
                    .as_object_mut()
                    .ok_or("Invalid shared attachment")?;
                let id = object
                    .get("id")
                    .and_then(Value::as_str)
                    .ok_or("Invalid shared attachment ID")?
                    .to_owned();
                let filename = object
                    .get("filename")
                    .and_then(Value::as_str)
                    .ok_or("Invalid shared attachment filename")?
                    .to_owned();
                let archive_path = object
                    .remove("archiveRelativePath")
                    .and_then(|value| value.as_str().map(str::to_owned))
                    .ok_or("Invalid shared attachment path")?;
                let relative_path =
                    managed_attachment_path(&snapshot.project_id, &story_id, &id, &filename);
                let source = previous
                    .git_repository
                    .as_ref()
                    .ok_or("Missing repository")?
                    .local_path
                    .clone();
                let source_path = PathBuf::from(source)
                    .join(".fs-user-stories")
                    .join(archive_path);
                let destination = config.attachments_root.join(&relative_path);
                if source_path.exists() {
                    fs::create_dir_all(destination.parent().expect("managed attachment parent"))
                        .map_err(|error| error.to_string())?;
                    fs::copy(source_path, destination).map_err(|error| error.to_string())?;
                }
                object.insert("relativePath".into(), Value::String(relative_path));
            }
            serde_json::from_value(value).map_err(|error| error.to_string())
        })
        .collect::<Result<Vec<_>, String>>()?;
    Ok(WorkspaceProject {
        id: snapshot.project_id,
        name: snapshot.name,
        prefix: snapshot.prefix,
        actors,
        stories,
        git_repository: previous.git_repository.clone(),
    })
}

fn mutate(
    config: &MCPServerConfig,
    project_id: &str,
    operation: WorkspaceCommand,
) -> Result<Value, String> {
    let mut store =
        WorkspaceStore::open(&config.database_path).map_err(|error| error.to_string())?;
    let mut projects = store.load_projects().map_err(|error| error.to_string())?;
    let index = projects
        .iter()
        .position(|project| project.id == project_id)
        .ok_or("Project not found")?;
    let updated = apply_workspace_command(projects[index].clone(), operation)
        .map_err(|error| error.to_string())?
        .project;
    projects[index] = updated.clone();
    store
        .save_projects(&projects)
        .map_err(|error| error.to_string())?;
    Ok(json!({"project": updated}))
}

fn list_stories(arguments: &Map<String, Value>, config: &MCPServerConfig) -> Result<Value, String> {
    let status_filter = arguments
        .get("status")
        .and_then(Value::as_str)
        .map(status)
        .transpose()?;
    let actor_id = arguments.get("actor_id").and_then(Value::as_str);
    let query = arguments
        .get("query")
        .and_then(Value::as_str)
        .map(str::to_lowercase);
    let project_filter = arguments.get("project_id").and_then(Value::as_str);
    let has_open = arguments.get("has_open_criteria").and_then(Value::as_bool);
    let created_after = arguments
        .get("created_after")
        .and_then(Value::as_str)
        .map(validate_date)
        .transpose()?;
    let created_before = arguments
        .get("created_before")
        .and_then(Value::as_str)
        .map(validate_date)
        .transpose()?;
    let stories = load_projects(config)?.into_iter().filter(|project| project_filter.is_none_or(|id| project.id == id)).flat_map(|project| project.stories.into_iter().map(move |story| (project.id.clone(), project.prefix.clone(), project.name.clone(), story))).filter(|(_, _, _, story)| status_filter.is_none_or(|status| story.status == status)).filter(|(_, _, _, story)| actor_id.is_none_or(|id| story.actor_id == id)).filter(|(_, _, _, story)| has_open.is_none_or(|open| story.acceptance_criteria.iter().any(|criterion| !criterion.is_met) == open)).filter(|(_, _, _, story)| query.as_ref().is_none_or(|query| format!("{} {} {} {}", story.title, story.want, story.outcome, story.notes).to_lowercase().contains(query))).filter(|(_, _, _, story)| created_after.as_ref().is_none_or(|date| &story.created_at >= date)).filter(|(_, _, _, story)| created_before.as_ref().is_none_or(|date| &story.created_at <= date)).map(|(project_id, prefix, project_name, story)| json!({"project_id": project_id, "project_name": project_name, "reference": format!("{}-{}", prefix, story.number), "story": story})).collect::<Vec<_>>();
    Ok(json!({"stories": stories}))
}

fn update_story(arguments: &Map<String, Value>, config: &MCPServerConfig) -> Result<Value, String> {
    let project_id = required(arguments, "project_id")?;
    let current = project(config, project_id)?
        .stories
        .into_iter()
        .find(|story| story.id == required(arguments, "story_id").unwrap_or_default())
        .ok_or("Story not found")?;
    mutate(
        config,
        project_id,
        WorkspaceCommand::UpdateStory {
            story_id: current.id,
            title: optional_or(arguments, "title", &current.title),
            actor_id: optional_or(arguments, "actor_id", &current.actor_id),
            want: optional_or(arguments, "want", &current.want),
            outcome: optional_or(arguments, "outcome", &current.outcome),
            acceptance_criteria: current.acceptance_criteria,
        },
    )
}

fn criteria_from(
    arguments: &Map<String, Value>,
) -> Result<Vec<WorkspaceAcceptanceCriterion>, String> {
    arguments
        .get("acceptance_criteria")
        .and_then(Value::as_array)
        .ok_or("acceptance_criteria is required")?
        .iter()
        .filter_map(Value::as_str)
        .map(|text| WorkspaceAcceptanceCriterion {
            id: String::new(),
            text: text.into(),
            is_met: false,
        })
        .collect::<Vec<_>>()
        .pipe(Ok)
}

fn attachments(arguments: &Map<String, Value>, config: &MCPServerConfig) -> Result<Value, String> {
    let story = story(arguments, config)?;
    Ok(json!({"attachments": story.attachments}))
}

fn attachment(arguments: &Map<String, Value>, config: &MCPServerConfig) -> Result<Value, String> {
    let attachment_id = required(arguments, "attachment_id")?;
    let attachment = story(arguments, config)?
        .attachments
        .into_iter()
        .find(|attachment| attachment.id == attachment_id)
        .ok_or("Attachment not found")?;
    Ok(
        json!({"attachment": attachment, "url": format!("http://127.0.0.1:{}/attachments/{}", config.port, attachment.id)}),
    )
}

fn story(
    arguments: &Map<String, Value>,
    config: &MCPServerConfig,
) -> Result<crate::workspace::WorkspaceStory, String> {
    project(config, required(arguments, "project_id")?)?
        .stories
        .into_iter()
        .find(|story| story.id == required(arguments, "story_id").unwrap_or_default())
        .ok_or_else(|| "Story not found".into())
}

fn add_attachments(
    arguments: &Map<String, Value>,
    config: &MCPServerConfig,
) -> Result<Value, String> {
    let project_id = required(arguments, "project_id")?;
    let story_id = required(arguments, "story_id")?;
    let paths = arguments
        .get("paths")
        .and_then(Value::as_array)
        .ok_or("paths is required")?;
    let mut attachments = Vec::new();
    for value in paths {
        let source = PathBuf::from(value.as_str().ok_or("paths must contain strings")?);
        let metadata =
            fs::metadata(&source).map_err(|_| format!("Cannot read {}", source.display()))?;
        if !metadata.is_file() {
            return Err(format!("{} is not a file", source.display()));
        }
        if metadata.len() > MAXIMUM_FILE_SIZE {
            return Err(format!(
                "{} exceeds the 10 MB attachment limit",
                source.display()
            ));
        }
        let id = Uuid::new_v4().to_string().to_uppercase();
        let filename = source
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or("attachment");
        let relative_path = managed_attachment_path(project_id, story_id, &id, filename);
        let destination = config.attachments_root.join(&relative_path);
        fs::create_dir_all(destination.parent().expect("attachment has parent"))
            .map_err(|error| error.to_string())?;
        fs::copy(&source, &destination).map_err(|error| error.to_string())?;
        let bytes = fs::read(&destination).map_err(|error| error.to_string())?;
        attachments.push(WorkspaceAttachment {
            id,
            filename: filename.into(),
            content_type: content_type(&source),
            byte_size: bytes.len() as i64,
            sha256: format!("{:x}", Sha256::digest(bytes)),
            relative_path,
            created_at: Utc::now().to_rfc3339(),
        });
    }
    mutate(
        config,
        project_id,
        WorkspaceCommand::AddAttachments {
            story_id: story_id.into(),
            attachments,
        },
    )
}

fn delete_attachment(
    arguments: &Map<String, Value>,
    config: &MCPServerConfig,
) -> Result<Value, String> {
    confirm(arguments)?;
    let project_id = required(arguments, "project_id")?;
    let story_id = required(arguments, "story_id")?;
    let attachment_id = required(arguments, "attachment_id")?;
    let existing = story(arguments, config)?
        .attachments
        .into_iter()
        .find(|attachment| attachment.id == attachment_id)
        .ok_or("Attachment not found")?;
    let result = mutate(
        config,
        project_id,
        WorkspaceCommand::RemoveAttachment {
            story_id: story_id.into(),
            attachment_id: attachment_id.into(),
        },
    )?;
    let path = config.attachments_root.join(existing.relative_path);
    if path.starts_with(&config.attachments_root) {
        let _ = fs::remove_file(path);
    }
    Ok(result)
}

fn attachment_response(path: &str, config: &MCPServerConfig) -> Response<std::io::Cursor<Vec<u8>>> {
    let id = path.trim_start_matches("/attachments/");
    let result = load_projects(config).ok().and_then(|projects| {
        projects
            .into_iter()
            .flat_map(|project| project.stories)
            .flat_map(|story| story.attachments)
            .find(|attachment| attachment.id == id)
    });
    let Some(attachment) = result else {
        return empty_response(StatusCode(404));
    };
    let file_path = config.attachments_root.join(&attachment.relative_path);
    if !file_path.starts_with(&config.attachments_root) {
        return empty_response(StatusCode(403));
    }
    match fs::read(file_path) {
        Ok(bytes) => Response::from_data(bytes)
            .with_header(header("Content-Type", &attachment.content_type))
            .with_header(header(
                "Content-Disposition",
                &format!(
                    "inline; filename=\"{}\"",
                    attachment.filename.replace('"', "")
                ),
            )),
        Err(_) => empty_response(StatusCode(404)),
    }
}

fn required<'a>(arguments: &'a Map<String, Value>, key: &str) -> Result<&'a str, String> {
    arguments
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| format!("{key} is required"))
}
fn optional(arguments: &Map<String, Value>, key: &str) -> String {
    arguments
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .into()
}
fn optional_or(arguments: &Map<String, Value>, key: &str, fallback: &str) -> String {
    arguments
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or(fallback)
        .trim()
        .into()
}
fn confirm(arguments: &Map<String, Value>) -> Result<(), String> {
    if arguments.get("confirm").and_then(Value::as_bool) == Some(true) {
        Ok(())
    } else {
        Err("This destructive action requires confirm=true".into())
    }
}
fn status(value: &str) -> Result<StoryStatus, String> {
    match value {
        "draft" => Ok(StoryStatus::Draft),
        "active" => Ok(StoryStatus::Active),
        "done" => Ok(StoryStatus::Done),
        _ => Err("status must be draft, active, or done".into()),
    }
}
fn stable_path_component(value: &str, length: usize) -> String {
    let digest = format!("{:x}", Sha256::digest(value.as_bytes()));
    digest[..length.min(digest.len())].to_owned()
}

fn safe_extension(filename: &str) -> Option<String> {
    let extension = Path::new(filename)
        .extension()
        .and_then(|value| value.to_str())?
        .to_ascii_lowercase();
    if extension.is_empty()
        || extension.len() > 10
        || !extension
            .chars()
            .all(|character| character.is_ascii_alphanumeric())
    {
        None
    } else {
        Some(extension)
    }
}

fn attachment_storage_name(id: &str, filename: &str) -> String {
    let stem = stable_path_component(id, 32);
    match safe_extension(filename) {
        Some(extension) => format!("{stem}.{extension}"),
        None => stem,
    }
}

fn managed_attachment_path(
    project_id: &str,
    story_id: &str,
    attachment_id: &str,
    filename: &str,
) -> String {
    format!(
        "{}/{}/{}",
        stable_path_component(project_id, 24),
        stable_path_component(story_id, 24),
        attachment_storage_name(attachment_id, filename)
    )
}

fn archive_attachment_path(story_id: &str, attachment_id: &str, filename: &str) -> String {
    format!(
        "attachments/{}/{}",
        stable_path_component(story_id, 24),
        attachment_storage_name(attachment_id, filename)
    )
}

fn repository_directory_name(project_id: &str) -> String {
    format!("p-{}", stable_path_component(project_id, 24))
}
fn content_type(path: &Path) -> String {
    match path
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase()
        .as_str()
    {
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "pdf" => "application/pdf",
        "txt" | "md" => "text/plain",
        _ => "application/octet-stream",
    }
    .into()
}

fn validate_date(value: &str) -> Result<String, String> {
    chrono::DateTime::parse_from_rfc3339(value)
        .map(|_| value.into())
        .map_err(|_| "created_after and created_before must be ISO 8601 timestamps".into())
}

fn tool_result(value: Value, is_error: bool) -> Value {
    json!({"content": [{"type": "text", "text": value.to_string()}], "isError": is_error})
}
fn rpc_success(id: Value, result: Value) -> Value {
    json!({"jsonrpc": "2.0", "id": id, "result": result})
}
fn rpc_error(id: Value, code: i64, message: &str) -> Value {
    json!({"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}})
}
fn json_response(value: Value, status: StatusCode) -> Response<std::io::Cursor<Vec<u8>>> {
    Response::from_data(value.to_string())
        .with_status_code(status)
        .with_header(header("Content-Type", "application/json; charset=utf-8"))
}
fn empty_response(status: StatusCode) -> Response<std::io::Cursor<Vec<u8>>> {
    Response::from_data(Vec::new()).with_status_code(status)
}
fn header(name: &str, value: &str) -> Header {
    Header::from_bytes(name, value).expect("valid HTTP header")
}

fn tool_definitions() -> Vec<Value> {
    let mut tools = Vec::new();
    for (name, description) in [
        (
            "about_app",
            "Describe FS User Stories and its local MCP service.",
        ),
        ("list_projects", "List local projects."),
        ("create_project", "Create a project."),
        (
            "update_project",
            "Rename a project or update its story prefix.",
        ),
        (
            "delete_project",
            "Delete a project and all of its data; requires confirm=true.",
        ),
        ("get_project", "Get a project and its stories."),
        ("get_repository_status", "Get local Git sharing status."),
        ("list_actors", "List project profiles."),
        ("create_actor", "Create a profile."),
        ("update_actor", "Update a profile."),
        ("delete_actor", "Delete a profile; requires confirm=true."),
        (
            "list_stories",
            "Search stories by project, profile, status, text, and open criteria.",
        ),
        ("get_story", "Get full story details."),
        ("create_story", "Create a story."),
        ("update_story", "Update a non-completed story."),
        ("duplicate_story", "Duplicate a story as a draft."),
        ("delete_story", "Delete a story; requires confirm=true."),
        ("add_acceptance_criterion", "Add a criterion."),
        ("set_acceptance_criterion", "Mark a criterion met or unmet."),
        (
            "delete_acceptance_criterion",
            "Delete a criterion; requires confirm=true.",
        ),
        ("set_story_status", "Set draft, active, or done."),
        ("update_notes", "Update the one optional story note."),
        ("list_attachments", "List story attachments."),
        (
            "add_attachments",
            "Copy local files into managed attachment storage.",
        ),
        (
            "get_attachment",
            "Get attachment metadata and loopback preview URL.",
        ),
        (
            "delete_attachment",
            "Delete an attachment; requires confirm=true.",
        ),
        (
            "connect_shared_repository",
            "Connect a project to an existing Git remote.",
        ),
        ("synchronize_project", "Synchronize a shared Git project."),
        (
            "create_share_invitation",
            "Create a Git sharing invitation.",
        ),
    ] {
        tools.push(json!({"name": name, "description": description, "inputSchema": {"type": "object", "additionalProperties": true}}));
    }
    tools
}

fn prompt_definitions() -> Vec<Value> {
    vec![
        json!({"name": "analyze_existing_project", "description": "Review a codebase and propose evidence-based profiles and user stories.", "arguments": [{"name": "project_id", "required": true}, {"name": "scope", "required": false}]}),
    ]
}

fn handle_prompt_get(
    id: Value,
    params: Option<&Map<String, Value>>,
    config: &MCPServerConfig,
) -> Value {
    let Some(arguments) = params
        .and_then(|value| value.get("arguments"))
        .and_then(Value::as_object)
    else {
        return rpc_error(id, -32602, "project_id is required");
    };
    let Ok(project) =
        required(arguments, "project_id").and_then(|project_id| project(config, project_id))
    else {
        return rpc_error(id, -32602, "Project not found");
    };
    let text = format!(
        "Analyze this existing software project and propose evidence-based FS User Stories. Project: {} ({})\nProfiles:\n{}\nStories:\n{}\nInspect the actual code first. Do not modify anything until the user approves.",
        project.name,
        project.id,
        project
            .actors
            .iter()
            .map(|actor| format!("- {}: {}", actor.name, actor.role))
            .collect::<Vec<_>>()
            .join("\n"),
        project
            .stories
            .iter()
            .map(|story| format!(
                "- {}-{} [{}] {}",
                project.prefix,
                story.number,
                story.status.as_str(),
                story.title
            ))
            .collect::<Vec<_>>()
            .join("\n")
    );
    rpc_success(
        id,
        json!({"description": "Review an existing codebase and propose evidence-based stories.", "messages": [{"role": "user", "content": {"type": "text", "text": text}}]}),
    )
}

trait Pipe: Sized {
    fn pipe<T>(self, function: impl FnOnce(Self) -> T) -> T {
        function(self)
    }
}
impl<T> Pipe for T {}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn rust_mcp_tools_create_and_query_workspace_data() {
        let directory = tempdir().expect("temporary directory");
        let config = MCPServerConfig {
            database_path: directory.path().join("workspace.sqlite3"),
            attachments_root: directory.path().join("attachments"),
            port: 49_999,
        };
        let project = create_project("MCP", "MCP", &config).expect("project");
        let mut arguments = Map::new();
        arguments.insert("project_id".into(), Value::String(project.id.clone()));
        arguments.insert("name".into(), Value::String("Developer".into()));
        execute_tool("create_actor", &arguments, &config).expect("actor");

        let actors = execute_tool("list_actors", &arguments, &config).expect("actors");
        assert_eq!(actors["actors"].as_array().expect("array").len(), 1);
        assert_eq!(
            load_projects(&config).expect("projects")[0].actors[0].name,
            "Developer"
        );
    }

    #[test]
    fn synchronization_refuses_to_overwrite_a_concurrent_local_edit() {
        let directory = tempdir().expect("temporary directory");
        let config = MCPServerConfig {
            database_path: directory.path().join("workspace.sqlite3"),
            attachments_root: directory.path().join("attachments"),
            port: 49_999,
        };
        let initial = create_project("Initial", "INI", &config).expect("project");
        let mut current = initial.clone();
        current.name = "Edited while syncing".into();
        assert!(matches!(
            ensure_workspace_unchanged(&initial, &current),
            Err(CoreError::WorkspaceChangedDuringSync)
        ));
    }

    #[test]
    fn attachment_paths_are_short_stable_and_cross_platform_safe() {
        let unsafe_name =
            "CON: Screenshot <draft> with a deliberately very long visible name...?*.PNG";
        let managed = managed_attachment_path(
            "project-with-a-long-user-controlled-identifier",
            "story-with-a-long-user-controlled-identifier",
            "attachment-with-a-long-user-controlled-identifier",
            unsafe_name,
        );
        let archived = archive_attachment_path(
            "story-with-a-long-user-controlled-identifier",
            "attachment-with-a-long-user-controlled-identifier",
            unsafe_name,
        );

        assert_eq!(managed.len(), 86);
        assert_eq!(archived.len(), 73);
        assert!(managed.ends_with(".png"));
        assert!(archived.ends_with(".png"));
        assert!(!managed.contains("CON"));
        assert!(!archived.contains(' '));
        assert_eq!(
            repository_directory_name("project-with-a-long-user-controlled-identifier").len(),
            26
        );
    }

    #[test]
    fn rust_imports_and_removes_managed_attachments_with_sqlite_as_source_of_truth() {
        let directory = tempdir().expect("temporary directory");
        let config = MCPServerConfig {
            database_path: directory.path().join("workspace.sqlite3"),
            attachments_root: directory.path().join("attachments"),
            port: 49_999,
        };
        let project = create_project("Attachments", "ATT", &config).expect("project");
        let project = apply_workspace_command(
            project,
            WorkspaceCommand::AddActor {
                name: "Developer".into(),
                role: String::new(),
            },
        )
        .expect("actor")
        .project;
        let actor_id = project.actors[0].id.clone();
        let project = apply_workspace_command(
            project,
            WorkspaceCommand::AddStory {
                title: "Attach a file".into(),
                actor_id,
                want: "a local copy".into(),
                outcome: "the source can move".into(),
                acceptance_criteria: vec![WorkspaceAcceptanceCriterion {
                    id: Uuid::new_v4().to_string().to_uppercase(),
                    text: "The file is preserved".into(),
                    is_met: false,
                }],
            },
        )
        .expect("story")
        .project;
        save_updated_project(&config, project.clone()).expect("save story");
        let story_id = project.stories[0].id.clone();
        let filename = format!(
            "{}2026-08-13 at 7.22.30 p.m..PNG",
            "Screenshot with a long visible name ".repeat(5)
        );
        let source = directory.path().join(&filename);
        fs::write(&source, b"managed attachment").expect("source file");

        let value = import_stored_attachments(
            config.database_path.clone(),
            config.attachments_root.clone(),
            project.id.clone(),
            story_id.clone(),
            vec![source],
        )
        .expect("import attachment");
        let imported: WorkspaceProject =
            serde_json::from_value(value["project"].clone()).expect("project result");
        let attachment = &imported.stories[0].attachments[0];
        assert_eq!(attachment.filename, filename);
        assert!(attachment.relative_path.len() <= 90);
        assert!(attachment.relative_path.ends_with(".png"));
        assert!(!attachment.relative_path.contains("Screenshot"));
        assert!(
            config
                .attachments_root
                .join(&attachment.relative_path)
                .exists()
        );
        assert!(!attachment.sha256.is_empty());

        remove_stored_attachment(
            config.database_path.clone(),
            config.attachments_root.clone(),
            project.id,
            story_id,
            attachment.id.clone(),
        )
        .expect("remove attachment");
        let stored = load_projects(&config).expect("load projects");
        assert!(stored[0].stories[0].attachments.is_empty());
        assert!(
            !config
                .attachments_root
                .join(&attachment.relative_path)
                .exists()
        );
    }
}
