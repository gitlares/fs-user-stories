// SPDX-License-Identifier: MIT

use serde::{Deserialize, Serialize};

use crate::protocol::CoreError;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProjectInvitation {
    pub format_version: u32,
    pub project_id: String,
    pub project_name: String,
    pub remote_url: String,
    pub default_branch: String,
}

impl ProjectInvitation {
    pub const FORMAT_VERSION: u32 = 1;

    pub fn new(
        project_id: String,
        project_name: String,
        remote_url: String,
        default_branch: String,
    ) -> Result<Self, CoreError> {
        if project_id.trim().is_empty() || project_name.trim().is_empty() {
            return Err(CoreError::InvalidInvitation(
                "Project id and name are required".into(),
            ));
        }
        validate_remote_url(&remote_url)?;
        if default_branch.trim().is_empty() {
            return Err(CoreError::InvalidInvitation(
                "Default branch is required".into(),
            ));
        }
        Ok(Self {
            format_version: Self::FORMAT_VERSION,
            project_id,
            project_name,
            remote_url,
            default_branch,
        })
    }

    pub fn encode(&self) -> Result<String, CoreError> {
        let bytes = serde_json::to_vec(self)?;
        use base64::Engine;
        Ok(base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes))
    }

    pub fn decode(value: &str) -> Result<Self, CoreError> {
        use base64::Engine;
        let bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD
            .decode(value)
            .map_err(|error| CoreError::InvalidInvitation(error.to_string()))?;
        let invitation: Self = serde_json::from_slice(&bytes)?;
        if invitation.format_version != Self::FORMAT_VERSION {
            return Err(CoreError::InvalidInvitation(format!(
                "Unsupported invitation version {}",
                invitation.format_version
            )));
        }
        validate_remote_url(&invitation.remote_url)?;
        Ok(invitation)
    }
}

pub fn validate_remote_url(value: &str) -> Result<(), CoreError> {
    let value = value.trim();
    let is_https = value.starts_with("https://");
    let is_ssh = value.starts_with("ssh://")
        || (value.contains('@') && value.contains(':') && !value.contains("//"));
    if !is_https && !is_ssh {
        return Err(CoreError::InvalidRemote(
            "Use an HTTPS or SSH repository URL".into(),
        ));
    }
    if value.contains('\n') || value.contains('\r') {
        return Err(CoreError::InvalidRemote("Repository URL is invalid".into()));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn invitation_round_trip_contains_no_credentials() {
        let invitation = ProjectInvitation::new(
            "project-id".into(),
            "Example".into(),
            "git@example.com:team/example.git".into(),
            "fs-user-stories".into(),
        )
        .unwrap();
        let encoded = invitation.encode().unwrap();
        assert_eq!(ProjectInvitation::decode(&encoded).unwrap(), invitation);
        assert!(!encoded.contains("token"));
    }

    #[test]
    fn rejects_local_and_insecure_remotes() {
        assert!(validate_remote_url("file:///tmp/repository").is_err());
        assert!(validate_remote_url("http://example.com/repository").is_err());
    }
}
