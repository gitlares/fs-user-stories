// SPDX-License-Identifier: MIT

use std::{
    fs,
    path::{Path, PathBuf},
};

use git2::{
    Cred, CredentialType, FetchOptions, IndexAddOption, PushOptions, RemoteCallbacks, Repository,
    RepositoryInitOptions, Signature,
    build::{CheckoutBuilder, RepoBuilder},
};

use crate::{
    archive::{AttachmentSources, ProjectSnapshot},
    invitation::normalize_remote_url,
    protocol::CoreError,
    sync::{ConflictResolution, MergeResult, apply_resolutions, merge_snapshots},
};
use serde::Serialize;

pub const DEFAULT_REMOTE: &str = "origin";
pub const SYNC_BRANCH: &str = "fs-user-stories";

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncOutcome {
    pub digest: String,
    pub snapshot: ProjectSnapshot,
}

#[derive(Clone, Debug)]
pub struct RepositoryEngine {
    root: PathBuf,
}

impl RepositoryEngine {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    pub fn create(
        &self,
        snapshot: &ProjectSnapshot,
        attachment_sources: &AttachmentSources,
    ) -> Result<String, CoreError> {
        fs::create_dir_all(&self.root)?;
        let repository = match Repository::open(&self.root) {
            Ok(repository) => repository,
            Err(_) => {
                let mut options = RepositoryInitOptions::new();
                options.initial_head(SYNC_BRANCH);
                Repository::init_opts(&self.root, &options)?
            }
        };
        ensure_sync_branch(&repository)?;
        let digest = snapshot.write_with_attachments(&self.root, attachment_sources)?;
        commit_archive(&repository, "Update user stories")?;
        Ok(digest)
    }

    pub fn connect(&self, remote_url: &str) -> Result<String, CoreError> {
        let remote_url = normalize_remote_url(remote_url)?;
        let repository = Repository::open(&self.root)?;
        ensure_sync_branch(&repository)?;
        match repository.find_remote(DEFAULT_REMOTE) {
            Ok(_) => repository.remote_set_url(DEFAULT_REMOTE, &remote_url)?,
            Err(_) => {
                repository.remote(DEFAULT_REMOTE, &remote_url)?;
            }
        }
        Ok(remote_url)
    }

    pub fn clone_shared(
        remote_url: &str,
        destination: &Path,
        access_token: Option<&str>,
    ) -> Result<ProjectSnapshot, CoreError> {
        let remote_url = normalize_remote_url(remote_url)?;
        if destination.exists() && destination.read_dir()?.next().is_some() {
            return Err(CoreError::RepositoryNotEmpty);
        }
        fs::create_dir_all(destination)?;
        let mut fetch = FetchOptions::new();
        fetch.remote_callbacks(remote_callbacks(access_token));
        let mut builder = RepoBuilder::new();
        builder.fetch_options(fetch);
        builder.branch(SYNC_BRANCH);
        builder.clone(&remote_url, destination)?;
        ProjectSnapshot::read(destination)
    }

    pub fn synchronize(
        &self,
        snapshot: &ProjectSnapshot,
        attachment_sources: &AttachmentSources,
        access_token: Option<&str>,
    ) -> Result<SyncOutcome, CoreError> {
        let repository = Repository::open(&self.root)?;
        ensure_sync_branch(&repository)?;
        let base = ProjectSnapshot::read(&self.root)?;
        let remote_branch_exists = fetch(&repository, access_token)?;
        let received_shared_changes =
            remote_branch_exists && fast_forward_if_possible(&repository)?;
        let synchronized = if received_shared_changes {
            let shared = ProjectSnapshot::read(&self.root)?;
            let result = merge_snapshots(&base, snapshot, &shared)?;
            if !result.conflicts.is_empty() {
                fs::write(pending_sync_path(&repository), serde_json::to_vec(&result)?)?;
                return Err(CoreError::SyncConflicts(serde_json::to_string(&result)?));
            }
            result.merged
        } else {
            snapshot.clone()
        };
        let digest = synchronized.write_with_attachments(&self.root, attachment_sources)?;
        commit_archive(&repository, "Update user stories")?;
        push(&repository, access_token)?;
        Ok(SyncOutcome {
            digest,
            snapshot: synchronized,
        })
    }

    pub fn resolve_synchronization(
        &self,
        resolutions: &[ConflictResolution],
        attachment_sources: &AttachmentSources,
        access_token: Option<&str>,
    ) -> Result<SyncOutcome, CoreError> {
        let repository = Repository::open(&self.root)?;
        ensure_sync_branch(&repository)?;
        let pending_path = pending_sync_path(&repository);
        if !pending_path.exists() {
            return Err(CoreError::NoPendingSync);
        }
        let result: MergeResult = serde_json::from_slice(&fs::read(&pending_path)?)?;
        let snapshot = apply_resolutions(result, resolutions)?;
        let digest = snapshot.write_with_attachments(&self.root, attachment_sources)?;
        commit_archive(&repository, "Resolve shared user stories")?;
        push(&repository, access_token)?;
        fs::remove_file(pending_path)?;
        Ok(SyncOutcome { digest, snapshot })
    }
}

fn pending_sync_path(repository: &Repository) -> PathBuf {
    repository.path().join("fs-user-stories-pending.json")
}

fn signature(repository: &Repository) -> Result<Signature<'static>, CoreError> {
    if let Ok(signature) = repository.signature() {
        return Ok(Signature::now(
            signature.name().unwrap_or("FS User Stories"),
            signature.email().unwrap_or("local@fs-user-stories.invalid"),
        )?);
    }
    Ok(Signature::now(
        "FS User Stories",
        "local@fs-user-stories.invalid",
    )?)
}

fn ensure_sync_branch(repository: &Repository) -> Result<(), CoreError> {
    let Ok(head) = repository.head() else {
        return Ok(());
    };
    if head.shorthand().ok() == Some(SYNC_BRANCH) {
        return Ok(());
    }
    let target = head.target().ok_or(CoreError::InvalidRepositoryState)?;
    let reference_name = format!("refs/heads/{SYNC_BRANCH}");
    if repository.find_reference(&reference_name).is_err() {
        repository.reference(
            &reference_name,
            target,
            false,
            "Use the isolated FS User Stories branch",
        )?;
    }
    repository.set_head(&reference_name)?;
    repository.checkout_head(Some(CheckoutBuilder::new().force()))?;
    Ok(())
}

fn commit_archive(repository: &Repository, message: &str) -> Result<(), CoreError> {
    let mut index = repository.index()?;
    index.add_all([".fs-user-stories"], IndexAddOption::DEFAULT, None)?;
    index.write()?;
    let tree_id = index.write_tree()?;
    let tree = repository.find_tree(tree_id)?;
    let author = signature(repository)?;
    let parent = repository
        .head()
        .ok()
        .and_then(|head| head.target())
        .and_then(|id| repository.find_commit(id).ok());
    if parent
        .as_ref()
        .is_some_and(|parent| parent.tree_id() == tree_id)
    {
        return Ok(());
    }
    let parents = parent.iter().collect::<Vec<_>>();
    repository.commit(Some("HEAD"), &author, &author, message, &tree, &parents)?;
    Ok(())
}

fn fetch(repository: &Repository, access_token: Option<&str>) -> Result<bool, CoreError> {
    let mut remote = repository.find_remote(DEFAULT_REMOTE)?;
    let mut options = FetchOptions::new();
    options.remote_callbacks(remote_callbacks(access_token));
    let refspec = format!("+refs/heads/{SYNC_BRANCH}:refs/remotes/{DEFAULT_REMOTE}/{SYNC_BRANCH}");
    match remote.fetch(&[&refspec], Some(&mut options), None) {
        Ok(()) => Ok(true),
        Err(error)
            if error.code() == git2::ErrorCode::NotFound
                || error.message().contains("couldn't find remote ref") =>
        {
            Ok(false)
        }
        Err(error) => Err(error.into()),
    }
}

fn fast_forward_if_possible(repository: &Repository) -> Result<bool, CoreError> {
    let fetch_head = match repository.find_reference("FETCH_HEAD") {
        Ok(reference) => reference,
        Err(_) => return Ok(false),
    };
    let annotated = repository.reference_to_annotated_commit(&fetch_head)?;
    let (analysis, _) = repository.merge_analysis(&[&annotated])?;
    if analysis.is_up_to_date() {
        return Ok(false);
    }
    if analysis.is_fast_forward() || analysis.is_unborn() {
        let reference_name = repository
            .head()
            .ok()
            .and_then(|head| head.name().ok().map(str::to_owned))
            .unwrap_or_else(|| format!("refs/heads/{SYNC_BRANCH}"));
        match repository.find_reference(&reference_name) {
            Ok(mut reference) => {
                reference.set_target(annotated.id(), "Synchronize FS User Stories")?;
            }
            Err(_) => {
                repository.reference(
                    &reference_name,
                    annotated.id(),
                    true,
                    "Synchronize FS User Stories",
                )?;
            }
        }
        repository.set_head(&reference_name)?;
        repository.checkout_head(Some(CheckoutBuilder::new().force()))?;
        return Ok(true);
    }
    Err(CoreError::SyncConflict)
}

fn push(repository: &Repository, access_token: Option<&str>) -> Result<(), CoreError> {
    let head = repository.head()?;
    let branch = head.shorthand().unwrap_or(SYNC_BRANCH);
    guard_sync_branch(branch)?;
    let refspec = format!("refs/heads/{branch}:refs/heads/{SYNC_BRANCH}");
    let mut remote = repository.find_remote(DEFAULT_REMOTE)?;
    let mut options = PushOptions::new();
    options.remote_callbacks(remote_callbacks(access_token));
    remote.push(&[&refspec], Some(&mut options))?;
    Ok(())
}

fn guard_sync_branch(branch: &str) -> Result<(), CoreError> {
    if branch != SYNC_BRANCH {
        return Err(CoreError::ProtectedBranch(branch.to_owned()));
    }
    Ok(())
}

fn remote_callbacks<'a>(access_token: Option<&'a str>) -> RemoteCallbacks<'a> {
    let mut callbacks = RemoteCallbacks::new();
    callbacks.credentials(move |_url, username, allowed| {
        if allowed.contains(CredentialType::USER_PASS_PLAINTEXT)
            && let Some(token) = access_token
        {
            return Cred::userpass_plaintext("x-access-token", token);
        }
        if allowed.contains(CredentialType::SSH_KEY) {
            return Cred::ssh_key_from_agent(username.unwrap_or("git"));
        }
        if allowed.contains(CredentialType::DEFAULT) {
            return Cred::default();
        }
        Err(git2::Error::from_str(
            "Authentication is required. Configure SSH access for this repository.",
        ))
    });
    callbacks
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_the_reserved_branch_can_be_published() {
        assert!(guard_sync_branch(SYNC_BRANCH).is_ok());
        assert!(guard_sync_branch("main").is_err());
        assert!(guard_sync_branch("master").is_err());
        assert!(guard_sync_branch("feature/login").is_err());
    }
}
