// SPDX-License-Identifier: MIT

use std::{thread, time::Duration};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use serde_json::{Value, json};

use crate::invitation::normalize_remote_url;
use crate::protocol::CoreError;

const API_VERSION: &str = "2022-11-28";
const DEVICE_CODE_URL: &str = "https://github.com/login/device/code";
const ACCESS_TOKEN_URL: &str = "https://github.com/login/oauth/access_token";
const API_ROOT: &str = "https://api.github.com";

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeviceAuthorization {
    pub device_code: String,
    pub user_code: String,
    pub verification_url: String,
    pub expires_at: String,
    pub interval: u64,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GitHubRepository {
    pub name: String,
    pub full_name: String,
    pub clone_url: String,
    pub web_url: String,
}

#[derive(Deserialize)]
struct DeviceCodeResponse {
    device_code: String,
    user_code: String,
    verification_uri: String,
    expires_in: i64,
    interval: u64,
}

#[derive(Deserialize)]
struct AccessTokenResponse {
    access_token: Option<String>,
    error: Option<String>,
    error_description: Option<String>,
}

#[derive(Deserialize)]
struct RepositoryResponse {
    name: String,
    full_name: String,
    clone_url: String,
    html_url: String,
}

pub fn begin_authorization(client_id: &str) -> Result<DeviceAuthorization, CoreError> {
    configured_client_id(client_id)?;
    let response: DeviceCodeResponse = post_form(
        DEVICE_CODE_URL,
        &[("client_id", client_id), ("scope", "repo")],
    )?;
    Ok(DeviceAuthorization {
        device_code: response.device_code,
        user_code: response.user_code,
        verification_url: response.verification_uri,
        expires_at: (Utc::now() + chrono::Duration::seconds(response.expires_in)).to_rfc3339(),
        interval: response.interval,
    })
}

pub fn finish_authorization(
    client_id: &str,
    authorization: &DeviceAuthorization,
) -> Result<String, CoreError> {
    configured_client_id(client_id)?;
    let expires_at = DateTime::parse_from_rfc3339(&authorization.expires_at)
        .map_err(|_| CoreError::GitHubInvalidResponse)?
        .with_timezone(&Utc);
    let mut interval = authorization.interval.max(1);
    while Utc::now() < expires_at {
        thread::sleep(Duration::from_secs(interval));
        let response: AccessTokenResponse = post_form(
            ACCESS_TOKEN_URL,
            &[
                ("client_id", client_id),
                ("device_code", authorization.device_code.as_str()),
                ("grant_type", "urn:ietf:params:oauth:grant-type:device_code"),
            ],
        )?;
        if let Some(token) = response.access_token {
            return Ok(token);
        }
        match response.error.as_deref() {
            Some("authorization_pending") => {}
            Some("slow_down") => interval += 5,
            Some("expired_token") => return Err(CoreError::GitHubAuthorizationExpired),
            Some("access_denied") => return Err(CoreError::GitHubAuthorizationDenied),
            Some(error) => {
                return Err(CoreError::GitHubApi(
                    response.error_description.unwrap_or_else(|| error.into()),
                ));
            }
            None => return Err(CoreError::GitHubInvalidResponse),
        }
    }
    Err(CoreError::GitHubAuthorizationExpired)
}

pub fn create_private_repository(
    name: &str,
    access_token: &str,
) -> Result<GitHubRepository, CoreError> {
    let base_name = repository_name(&format!("{name}-user-stories"));
    for attempt in 1..=50 {
        let candidate = if attempt == 1 {
            base_name.clone()
        } else {
            format!("{base_name}-{attempt}")
        };
        let response = api_request(
            "POST",
            &format!("{API_ROOT}/user/repos"),
            access_token,
            json!({
                "name": candidate,
                "description": "User stories shared with FS User Stories",
                "private": true,
                "auto_init": false,
                "has_issues": false,
                "has_projects": false,
                "has_wiki": false
            }),
        )?;
        if response.status == 422 && repository_name_conflict(&response.body) {
            continue;
        }
        ensure_status(&response, &[201])?;
        let repository: RepositoryResponse =
            serde_json::from_slice(&response.body).map_err(|_| CoreError::GitHubInvalidResponse)?;
        return Ok(GitHubRepository {
            name: repository.name,
            full_name: repository.full_name,
            clone_url: repository.clone_url,
            web_url: repository.html_url,
        });
    }
    Err(CoreError::GitHubApi(
        "GitHub could not find an available repository name".into(),
    ))
}

pub fn invite_collaborator(
    username: &str,
    repository_url: &str,
    access_token: &str,
) -> Result<(), CoreError> {
    let repository = github_repository_path(repository_url)
        .ok_or_else(|| CoreError::GitHubApi("This is not a GitHub repository".into()))?;
    let username = username.trim();
    if !is_github_username(username) {
        return Err(CoreError::GitHubApi(
            "Enter the collaborator's GitHub username (not an email address).".into(),
        ));
    }
    let repository_info = api_request(
        "GET",
        &format!("{API_ROOT}/repos/{repository}"),
        access_token,
        json!({}),
    )?;
    ensure_status(&repository_info, &[200])?;
    let can_manage = serde_json::from_slice::<Value>(&repository_info.body)
        .ok()
        .and_then(|value| value.get("permissions").cloned())
        .and_then(|permissions| permissions.get("admin").and_then(Value::as_bool))
        .unwrap_or(false);
    if !can_manage {
        return Err(CoreError::GitHubApi(
            "No tienes permisos para invitar colaboradores. Debe hacerlo el propietario o un administrador del repositorio.".into(),
        ));
    }
    let response = api_request(
        "PUT",
        &format!("{API_ROOT}/repos/{repository}/collaborators/{username}"),
        access_token,
        json!({"permission": "push"}),
    )?;
    ensure_collaborator_invite_status(&response)
}

fn is_github_username(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 39
        && !value.starts_with('-')
        && !value.ends_with('-')
        && !value.contains("--")
        && value
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || character == '-')
}

struct ApiResponse {
    status: u16,
    body: Vec<u8>,
}

fn api_request(
    method: &str,
    url: &str,
    access_token: &str,
    body: Value,
) -> Result<ApiResponse, CoreError> {
    let authorization = format!("Bearer {access_token}");
    let agent = github_agent();
    let result = match method {
        "POST" => agent
            .post(url)
            .header("Accept", "application/vnd.github+json")
            .header("Authorization", &authorization)
            .header("X-GitHub-Api-Version", API_VERSION)
            .header("User-Agent", "FS-User-Stories")
            .send_json(body),
        "PUT" => agent
            .put(url)
            .header("Accept", "application/vnd.github+json")
            .header("Authorization", &authorization)
            .header("X-GitHub-Api-Version", API_VERSION)
            .header("User-Agent", "FS-User-Stories")
            .send_json(body),
        _ => return Err(CoreError::GitHubInvalidResponse),
    };
    read_response(result)
}

fn post_form<T: DeserializeOwned>(url: &str, values: &[(&str, &str)]) -> Result<T, CoreError> {
    let response = github_agent()
        .post(url)
        .header("Accept", "application/json")
        .send_form(values.iter().copied());
    let response = read_response(response)?;
    ensure_status(&response, &[200])?;
    serde_json::from_slice(&response.body).map_err(|_| CoreError::GitHubInvalidResponse)
}

fn github_agent() -> ureq::Agent {
    ureq::Agent::config_builder()
        .http_status_as_error(false)
        .build()
        .into()
}

fn read_response(
    result: Result<ureq::http::Response<ureq::Body>, ureq::Error>,
) -> Result<ApiResponse, CoreError> {
    let mut response = match result {
        Ok(response) => response,
        Err(ureq::Error::StatusCode(code)) => {
            return Ok(ApiResponse {
                status: code,
                body: Vec::new(),
            });
        }
        Err(error) => return Err(CoreError::GitHubApi(error.to_string())),
    };
    let status = response.status().as_u16();
    let body = response
        .body_mut()
        .read_to_vec()
        .map_err(|error| CoreError::GitHubApi(error.to_string()))?;
    Ok(ApiResponse { status, body })
}

fn ensure_status(response: &ApiResponse, expected: &[u16]) -> Result<(), CoreError> {
    if expected.contains(&response.status) {
        return Ok(());
    }
    let message = serde_json::from_slice::<Value>(&response.body)
        .ok()
        .and_then(|value| {
            value
                .get("message")
                .and_then(Value::as_str)
                .map(str::to_owned)
        })
        .unwrap_or_else(|| format!("GitHub returned HTTP {}", response.status));
    Err(CoreError::GitHubApi(message))
}

fn ensure_collaborator_invite_status(response: &ApiResponse) -> Result<(), CoreError> {
    if [201, 204].contains(&response.status) {
        return Ok(());
    }

    let github_message = serde_json::from_slice::<Value>(&response.body)
        .ok()
        .and_then(|value| {
            value
                .get("message")
                .and_then(Value::as_str)
                .map(str::to_owned)
        });

    let message = match response.status {
        401 | 403 => {
            "No tienes permisos para invitar colaboradores en este repositorio. Debe hacerlo el propietario o un administrador del repositorio.".to_owned()
        }
        404 => {
            "No se encontró el repositorio o el usuario de GitHub. Comprueba el nombre exacto y tus permisos.".to_owned()
        }
        422 => {
            format!(
                "GitHub rechazó la invitación. Comprueba que el usuario exista, que no seas tú mismo y que no haya una invitación pendiente.{}",
                github_message
                    .filter(|message| message != "Validation Failed")
                    .map(|message| format!(" Detalle: {message}"))
                    .unwrap_or_default()
            )
        }
        _ => github_message.unwrap_or_else(|| format!("GitHub returned HTTP {}", response.status)),
    };

    Err(CoreError::GitHubApi(message))
}

fn repository_name(value: &str) -> String {
    let mut output = String::new();
    let mut separator = false;
    for character in value.to_lowercase().chars() {
        if character.is_alphanumeric() {
            output.push(character);
            separator = false;
        } else if !output.is_empty() && !separator {
            output.push('-');
            separator = true;
        }
    }
    while output.ends_with('-') {
        output.pop();
    }
    if output.is_empty() {
        output = "fs-user-stories".into();
    }
    output.chars().take(90).collect()
}

fn github_repository_path(value: &str) -> Option<String> {
    let canonical = normalize_remote_url(value).ok()?;
    let normalized = canonical.trim_end_matches(".git");
    let path = if let Some(path) = normalized.strip_prefix("git@github.com:") {
        path
    } else if let Some(path) = normalized.strip_prefix("https://github.com/") {
        path
    } else {
        normalized.strip_prefix("ssh://git@github.com/")?
    };
    let parts = path.split('/').collect::<Vec<_>>();
    (parts.len() == 2 && parts.iter().all(|part| !part.is_empty())).then(|| path.into())
}

pub fn is_github_repository_url(value: &str) -> bool {
    github_repository_path(value).is_some()
}

fn repository_name_conflict(body: &[u8]) -> bool {
    let Ok(value) = serde_json::from_slice::<Value>(body) else {
        return false;
    };
    value["errors"].as_array().is_some_and(|errors| {
        errors.iter().any(|error| {
            error["field"] == "name"
                && matches!(
                    error["code"].as_str(),
                    Some("already_exists") | Some("custom")
                )
        })
    })
}

fn configured_client_id(value: &str) -> Result<(), CoreError> {
    if value.trim().is_empty() || value == "YOUR_GITHUB_OAUTH_CLIENT_ID" {
        Err(CoreError::GitHubNotConfigured)
    } else {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_repository_names() {
        assert_eq!(repository_name("Nuboo Marketplace!"), "nuboo-marketplace");
    }

    #[test]
    fn accepts_supported_github_remote_formats() {
        assert_eq!(
            github_repository_path("https://github.com/gitlares/example.git"),
            Some("gitlares/example".into())
        );
        assert_eq!(
            github_repository_path("git@github.com:gitlares/example.git"),
            Some("gitlares/example".into())
        );
        assert!(github_repository_path("https://gitlab.com/example/repo").is_none());
    }

    #[test]
    fn accepts_valid_github_usernames() {
        assert!(is_github_username("octocat"));
        assert!(is_github_username("fs-user-stories"));
        assert!(!is_github_username("person@example.com"));
        assert!(!is_github_username("-octocat"));
        assert!(!is_github_username("octocat-"));
    }
}
