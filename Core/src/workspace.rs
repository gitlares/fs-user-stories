// SPDX-License-Identifier: MIT

use chrono::Utc;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::markdown::PortableStory;
use crate::protocol::CoreError;

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceProject {
    pub id: String,
    pub name: String,
    pub prefix: String,
    pub actors: Vec<WorkspaceActor>,
    pub stories: Vec<WorkspaceStory>,
    pub git_repository: Option<WorkspaceGitRepositoryLink>,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceActor {
    pub id: String,
    pub name: String,
    pub role: String,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceStory {
    pub id: String,
    pub number: i64,
    pub title: String,
    pub actor_id: String,
    pub want: String,
    pub outcome: String,
    pub notes: String,
    pub acceptance_criteria: Vec<WorkspaceAcceptanceCriterion>,
    pub attachments: Vec<WorkspaceAttachment>,
    pub status: StoryStatus,
    pub created_at: String,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceAcceptanceCriterion {
    pub id: String,
    pub text: String,
    pub is_met: bool,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceAttachment {
    pub id: String,
    pub filename: String,
    pub content_type: String,
    pub byte_size: i64,
    pub sha256: String,
    pub relative_path: String,
    pub created_at: String,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceGitRepositoryLink {
    pub local_path: String,
    pub remote_url: Option<String>,
    pub default_branch: String,
    pub last_synced_digest: Option<String>,
    pub last_synced_at: Option<String>,
}

#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum StoryStatus {
    Draft,
    Active,
    Done,
}

impl StoryStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Draft => "draft",
            Self::Active => "active",
            Self::Done => "done",
        }
    }
}

#[derive(Debug, Deserialize)]
#[serde(tag = "operation", rename_all = "snake_case")]
pub enum WorkspaceCommand {
    UpdateProject {
        name: String,
        prefix: String,
    },
    AddActor {
        name: String,
        role: String,
    },
    UpdateActor {
        actor_id: String,
        name: String,
        role: String,
    },
    DeleteActor {
        actor_id: String,
    },
    AddStory {
        title: String,
        actor_id: String,
        want: String,
        outcome: String,
        acceptance_criteria: Vec<WorkspaceAcceptanceCriterion>,
    },
    UpdateStory {
        story_id: String,
        title: String,
        actor_id: String,
        want: String,
        outcome: String,
        acceptance_criteria: Vec<WorkspaceAcceptanceCriterion>,
    },
    DuplicateStory {
        story_id: String,
        copy_title: String,
    },
    DeleteStory {
        story_id: String,
    },
    ImportStories {
        stories: Vec<PortableStory>,
        imported_profile_name: String,
    },
    AddAttachments {
        story_id: String,
        attachments: Vec<WorkspaceAttachment>,
    },
    RemoveAttachment {
        story_id: String,
        attachment_id: String,
    },
    SetStoryStatus {
        story_id: String,
        status: StoryStatus,
    },
    SetAcceptanceCriterion {
        story_id: String,
        criterion_id: String,
        is_met: bool,
    },
    ToggleAcceptanceCriterion {
        story_id: String,
        criterion_id: String,
    },
    AddAcceptanceCriterion {
        story_id: String,
        text: String,
    },
    DeleteAcceptanceCriterion {
        story_id: String,
        criterion_id: String,
    },
    UpdateStoryNotes {
        story_id: String,
        notes: String,
    },
}

#[derive(Clone, Debug, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceCommandResult {
    pub project: WorkspaceProject,
}

/// Shared query semantics for the macOS interface and MCP.  Keeping this in
/// the core prevents a search in the UI from silently differing from an agent
/// search against the same SQLite workspace.
#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceStoryQuery {
    pub project_id: Option<String>,
    pub actor_id: Option<String>,
    pub status: Option<StoryStatus>,
    pub text: Option<String>,
    pub created_after: Option<String>,
    pub created_before: Option<String>,
    pub has_open_criteria: Option<bool>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceStoryMatch {
    pub project: WorkspaceProject,
    pub story: WorkspaceStory,
}

pub fn filter_stories(
    projects: &[WorkspaceProject],
    query: &WorkspaceStoryQuery,
) -> Result<Vec<WorkspaceStoryMatch>, CoreError> {
    let text = query
        .text
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_lowercase);
    let created_after = query
        .created_after
        .as_deref()
        .map(parse_workspace_date)
        .transpose()?;
    let created_before = query
        .created_before
        .as_deref()
        .map(parse_workspace_date)
        .transpose()?;
    Ok(projects
        .iter()
        .filter(|project| query.project_id.as_ref().is_none_or(|id| &project.id == id))
        .flat_map(|project| {
            let text = text.clone();
            project.stories.iter().filter_map(move |story| {
                if query
                    .actor_id
                    .as_ref()
                    .is_some_and(|id| &story.actor_id != id)
                    || query.status.is_some_and(|status| story.status != status)
                {
                    return None;
                }
                let created_at = parse_workspace_date(&story.created_at).ok()?;
                if created_after.is_some_and(|date| created_at < date)
                    || created_before.is_some_and(|date| created_at > date)
                {
                    return None;
                }
                if query.has_open_criteria.is_some_and(|required| {
                    story
                        .acceptance_criteria
                        .iter()
                        .any(|criterion| !criterion.is_met)
                        != required
                }) {
                    return None;
                }
                if let Some(text) = &text {
                    let actor = project
                        .actors
                        .iter()
                        .find(|actor| actor.id == story.actor_id);
                    let searchable = format!(
                        "{} {} {} {} {} {} {}",
                        story.title,
                        story.want,
                        story.outcome,
                        story.notes,
                        actor.map(|actor| actor.name.as_str()).unwrap_or_default(),
                        actor.map(|actor| actor.role.as_str()).unwrap_or_default(),
                        story
                            .acceptance_criteria
                            .iter()
                            .map(|criterion| criterion.text.as_str())
                            .collect::<Vec<_>>()
                            .join(" ")
                    )
                    .to_lowercase();
                    if !searchable.contains(text) {
                        return None;
                    }
                }
                Some(WorkspaceStoryMatch {
                    project: project.clone(),
                    story: story.clone(),
                })
            })
        })
        .collect())
}

fn parse_workspace_date(value: &str) -> Result<chrono::DateTime<chrono::FixedOffset>, CoreError> {
    chrono::DateTime::parse_from_rfc3339(value)
        .map_err(|_| CoreError::InvalidWorkspaceDate(value.into()))
}

pub fn apply_workspace_command(
    mut project: WorkspaceProject,
    command: WorkspaceCommand,
) -> Result<WorkspaceCommandResult, CoreError> {
    match command {
        WorkspaceCommand::UpdateProject { name, prefix } => {
            project.name = required(name, CoreError::WorkspaceNameRequired)?;
            project.prefix = required(prefix, CoreError::WorkspacePrefixRequired)?.to_uppercase();
        }
        WorkspaceCommand::AddActor { name, role } => {
            project.actors.push(WorkspaceActor {
                id: new_id(),
                name: required(name, CoreError::WorkspaceNameRequired)?,
                role: role.trim().into(),
            });
        }
        WorkspaceCommand::UpdateActor {
            actor_id,
            name,
            role,
        } => {
            let actor = project
                .actors
                .iter_mut()
                .find(|actor| actor.id == actor_id)
                .ok_or(CoreError::WorkspaceActorNotFound)?;
            actor.name = required(name, CoreError::WorkspaceNameRequired)?;
            actor.role = role.trim().into();
        }
        WorkspaceCommand::DeleteActor { actor_id } => {
            if project
                .stories
                .iter()
                .any(|story| story.actor_id == actor_id)
            {
                return Err(CoreError::WorkspaceActorInUse);
            }
            let index = project
                .actors
                .iter()
                .position(|actor| actor.id == actor_id)
                .ok_or(CoreError::WorkspaceActorNotFound)?;
            project.actors.remove(index);
        }
        WorkspaceCommand::AddStory {
            title,
            actor_id,
            want,
            outcome,
            acceptance_criteria,
        } => {
            validate_story_input(
                &project,
                &actor_id,
                &title,
                &want,
                &outcome,
                &acceptance_criteria,
            )?;
            project.stories.push(WorkspaceStory {
                id: new_id(),
                number: next_story_number(&project),
                title: title.trim().into(),
                actor_id,
                want: want.trim().into(),
                outcome: outcome.trim().into(),
                notes: String::new(),
                acceptance_criteria: normalized_criteria(acceptance_criteria)?,
                attachments: vec![],
                status: StoryStatus::Draft,
                created_at: Utc::now().to_rfc3339(),
            });
        }
        WorkspaceCommand::UpdateStory {
            story_id,
            title,
            actor_id,
            want,
            outcome,
            acceptance_criteria,
        } => {
            validate_story_input(
                &project,
                &actor_id,
                &title,
                &want,
                &outcome,
                &acceptance_criteria,
            )?;
            let story = editable_story_mut(&mut project, &story_id)?;
            story.title = title.trim().into();
            story.actor_id = actor_id;
            story.want = want.trim().into();
            story.outcome = outcome.trim().into();
            story.acceptance_criteria = normalized_criteria(acceptance_criteria)?;
        }
        WorkspaceCommand::DuplicateStory {
            story_id,
            copy_title,
        } => {
            let source = project
                .stories
                .iter()
                .find(|story| story.id == story_id)
                .cloned()
                .ok_or(CoreError::WorkspaceStoryNotFound)?;
            project.stories.push(WorkspaceStory {
                id: new_id(),
                number: next_story_number(&project),
                title: required(copy_title, CoreError::WorkspaceStoryTitleRequired)?,
                actor_id: source.actor_id,
                want: source.want,
                outcome: source.outcome,
                notes: source.notes,
                acceptance_criteria: source
                    .acceptance_criteria
                    .into_iter()
                    .map(|criterion| WorkspaceAcceptanceCriterion {
                        id: new_id(),
                        text: criterion.text,
                        is_met: false,
                    })
                    .collect(),
                attachments: vec![],
                status: StoryStatus::Draft,
                created_at: Utc::now().to_rfc3339(),
            });
        }
        WorkspaceCommand::DeleteStory { story_id } => {
            let index = project
                .stories
                .iter()
                .position(|story| story.id == story_id)
                .ok_or(CoreError::WorkspaceStoryNotFound)?;
            project.stories.remove(index);
        }
        WorkspaceCommand::ImportStories {
            stories,
            imported_profile_name,
        } => {
            for portable in stories {
                let profile_name = portable.profile_name.trim();
                let actor_id = project
                    .actors
                    .iter()
                    .find(|actor| actor.name.eq_ignore_ascii_case(profile_name))
                    .map(|actor| actor.id.clone())
                    .unwrap_or_else(|| {
                        let id = new_id();
                        project.actors.push(WorkspaceActor {
                            id: id.clone(),
                            name: if profile_name.is_empty() {
                                imported_profile_name.clone()
                            } else {
                                profile_name.into()
                            },
                            role: portable.profile_description.trim().into(),
                        });
                        id
                    });
                project.stories.push(WorkspaceStory {
                    id: new_id(),
                    number: next_story_number(&project),
                    title: portable.title.trim().into(),
                    actor_id,
                    want: portable.want.trim().into(),
                    outcome: portable.outcome.trim().into(),
                    notes: portable.notes,
                    acceptance_criteria: portable
                        .acceptance_criteria
                        .into_iter()
                        .map(|criterion| WorkspaceAcceptanceCriterion {
                            id: new_id(),
                            text: criterion.text.trim().into(),
                            is_met: criterion.is_met,
                        })
                        .collect(),
                    attachments: vec![],
                    status: serde_json::from_value(serde_json::Value::String(portable.status))?,
                    created_at: portable.created_at,
                });
            }
        }
        WorkspaceCommand::AddAttachments {
            story_id,
            attachments,
        } => {
            if attachments.is_empty() {
                return Err(CoreError::WorkspaceAttachmentsRequired);
            }
            let story = editable_story_mut(&mut project, &story_id)?;
            if story.attachments.len() + attachments.len() > 10 {
                return Err(CoreError::WorkspaceAttachmentLimit);
            }
            let existing_size = story
                .attachments
                .iter()
                .map(|attachment| attachment.byte_size)
                .sum::<i64>();
            let added_size = attachments
                .iter()
                .map(|attachment| attachment.byte_size)
                .sum::<i64>();
            if existing_size + added_size > 50 * 1_024 * 1_024 {
                return Err(CoreError::WorkspaceAttachmentSizeLimit);
            }
            story.attachments.extend(attachments);
        }
        WorkspaceCommand::RemoveAttachment {
            story_id,
            attachment_id,
        } => {
            let story = editable_story_mut(&mut project, &story_id)?;
            let index = story
                .attachments
                .iter()
                .position(|attachment| attachment.id == attachment_id)
                .ok_or(CoreError::WorkspaceAttachmentNotFound)?;
            story.attachments.remove(index);
        }
        WorkspaceCommand::SetStoryStatus { story_id, status } => {
            let story = find_story_mut(&mut project, &story_id)?;
            if status == StoryStatus::Done
                && (story.acceptance_criteria.is_empty()
                    || story
                        .acceptance_criteria
                        .iter()
                        .any(|criterion| !criterion.is_met))
            {
                return Err(CoreError::IncompleteAcceptanceCriteria);
            }
            story.status = status;
        }
        WorkspaceCommand::SetAcceptanceCriterion {
            story_id,
            criterion_id,
            is_met,
        } => {
            let story = editable_story_mut(&mut project, &story_id)?;
            let criterion = find_criterion_mut(story, &criterion_id)?;
            criterion.is_met = is_met;
        }
        WorkspaceCommand::ToggleAcceptanceCriterion {
            story_id,
            criterion_id,
        } => {
            let story = editable_story_mut(&mut project, &story_id)?;
            let criterion = find_criterion_mut(story, &criterion_id)?;
            criterion.is_met = !criterion.is_met;
        }
        WorkspaceCommand::AddAcceptanceCriterion { story_id, text } => {
            let text = text.trim();
            if text.is_empty() {
                return Err(CoreError::AcceptanceCriterionRequired);
            }
            let story = editable_story_mut(&mut project, &story_id)?;
            story
                .acceptance_criteria
                .push(WorkspaceAcceptanceCriterion {
                    id: new_id(),
                    text: text.into(),
                    is_met: false,
                });
        }
        WorkspaceCommand::DeleteAcceptanceCriterion {
            story_id,
            criterion_id,
        } => {
            let story = editable_story_mut(&mut project, &story_id)?;
            let index = story
                .acceptance_criteria
                .iter()
                .position(|criterion| criterion.id == criterion_id)
                .ok_or(CoreError::WorkspaceCriterionNotFound)?;
            story.acceptance_criteria.remove(index);
        }
        WorkspaceCommand::UpdateStoryNotes { story_id, notes } => {
            let story = editable_story_mut(&mut project, &story_id)?;
            story.notes = notes.trim().into();
        }
    }

    Ok(WorkspaceCommandResult { project })
}

fn required(value: String, error: CoreError) -> Result<String, CoreError> {
    let value = value.trim();
    if value.is_empty() {
        Err(error)
    } else {
        Ok(value.into())
    }
}

fn new_id() -> String {
    Uuid::new_v4().to_string().to_uppercase()
}

fn next_story_number(project: &WorkspaceProject) -> i64 {
    project
        .stories
        .iter()
        .map(|story| story.number)
        .max()
        .unwrap_or(0)
        + 1
}

fn normalized_criteria(
    criteria: Vec<WorkspaceAcceptanceCriterion>,
) -> Result<Vec<WorkspaceAcceptanceCriterion>, CoreError> {
    let criteria = criteria
        .into_iter()
        .filter_map(|criterion| {
            let text = criterion.text.trim();
            (!text.is_empty()).then(|| WorkspaceAcceptanceCriterion {
                id: if criterion.id.is_empty() {
                    new_id()
                } else {
                    criterion.id
                },
                text: text.into(),
                is_met: criterion.is_met,
            })
        })
        .collect::<Vec<_>>();
    if criteria.is_empty() {
        Err(CoreError::AcceptanceCriterionRequired)
    } else {
        Ok(criteria)
    }
}

fn validate_story_input(
    project: &WorkspaceProject,
    actor_id: &str,
    title: &str,
    want: &str,
    outcome: &str,
    criteria: &[WorkspaceAcceptanceCriterion],
) -> Result<(), CoreError> {
    required(title.into(), CoreError::WorkspaceStoryTitleRequired)?;
    required(want.into(), CoreError::WorkspaceStoryWantRequired)?;
    required(outcome.into(), CoreError::WorkspaceStoryOutcomeRequired)?;
    if !project.actors.iter().any(|actor| actor.id == actor_id) {
        return Err(CoreError::WorkspaceActorNotFound);
    }
    if criteria
        .iter()
        .all(|criterion| criterion.text.trim().is_empty())
    {
        return Err(CoreError::AcceptanceCriterionRequired);
    }
    Ok(())
}

fn find_story_mut<'a>(
    project: &'a mut WorkspaceProject,
    story_id: &str,
) -> Result<&'a mut WorkspaceStory, CoreError> {
    project
        .stories
        .iter_mut()
        .find(|story| story.id == story_id)
        .ok_or(CoreError::WorkspaceStoryNotFound)
}

fn editable_story_mut<'a>(
    project: &'a mut WorkspaceProject,
    story_id: &str,
) -> Result<&'a mut WorkspaceStory, CoreError> {
    let story = find_story_mut(project, story_id)?;
    if story.status == StoryStatus::Done {
        return Err(CoreError::CompletedStoryReadOnly);
    }
    Ok(story)
}

fn find_criterion_mut<'a>(
    story: &'a mut WorkspaceStory,
    criterion_id: &str,
) -> Result<&'a mut WorkspaceAcceptanceCriterion, CoreError> {
    story
        .acceptance_criteria
        .iter_mut()
        .find(|criterion| criterion.id == criterion_id)
        .ok_or(CoreError::WorkspaceCriterionNotFound)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn project() -> WorkspaceProject {
        WorkspaceProject {
            id: "project".into(),
            name: "Example".into(),
            prefix: "EX".into(),
            actors: vec![],
            stories: vec![WorkspaceStory {
                id: "story".into(),
                number: 1,
                title: "Ship core".into(),
                actor_id: "actor".into(),
                want: "Rules in Rust".into(),
                outcome: "A portable core".into(),
                notes: "".into(),
                acceptance_criteria: vec![WorkspaceAcceptanceCriterion {
                    id: "criterion".into(),
                    text: "Rules work".into(),
                    is_met: false,
                }],
                attachments: vec![],
                status: StoryStatus::Active,
                created_at: "2026-08-14T00:00:00Z".into(),
            }],
            git_repository: None,
        }
    }

    #[test]
    fn done_requires_all_acceptance_criteria() {
        let error = apply_workspace_command(
            project(),
            WorkspaceCommand::SetStoryStatus {
                story_id: "story".into(),
                status: StoryStatus::Done,
            },
        )
        .expect_err("unmet criterion must prevent completion");
        assert!(matches!(error, CoreError::IncompleteAcceptanceCriteria));
    }

    #[test]
    fn completed_stories_are_read_only() {
        let mut source = project();
        source.stories[0].acceptance_criteria[0].is_met = true;
        let completed = apply_workspace_command(
            source,
            WorkspaceCommand::SetStoryStatus {
                story_id: "story".into(),
                status: StoryStatus::Done,
            },
        )
        .expect("story should complete")
        .project;

        let error = apply_workspace_command(
            completed,
            WorkspaceCommand::UpdateStoryNotes {
                story_id: "story".into(),
                notes: "No edits".into(),
            },
        )
        .expect_err("completed story must remain read-only");
        assert!(matches!(error, CoreError::CompletedStoryReadOnly));
    }

    #[test]
    fn adding_a_criterion_trims_text_and_generates_an_identifier() {
        let result = apply_workspace_command(
            project(),
            WorkspaceCommand::AddAcceptanceCriterion {
                story_id: "story".into(),
                text: "  Portable rule  ".into(),
            },
        )
        .expect("criterion should be added");
        let criterion = result.project.stories[0]
            .acceptance_criteria
            .last()
            .expect("new criterion");
        assert_eq!(criterion.text, "Portable rule");
        assert!(Uuid::parse_str(&criterion.id).is_ok());
    }

    #[test]
    fn profile_and_story_crud_stay_inside_the_workspace_core() {
        let with_actor = apply_workspace_command(
            project(),
            WorkspaceCommand::AddActor {
                name: " Developer ".into(),
                role: " Builds ".into(),
            },
        )
        .expect("actor should be created")
        .project;
        let actor_id = with_actor.actors.last().expect("new actor").id.clone();
        let with_story = apply_workspace_command(
            with_actor,
            WorkspaceCommand::AddStory {
                title: " Create ".into(),
                actor_id,
                want: " a core ".into(),
                outcome: " a portable app ".into(),
                acceptance_criteria: vec![WorkspaceAcceptanceCriterion {
                    id: String::new(),
                    text: " Works ".into(),
                    is_met: false,
                }],
            },
        )
        .expect("story should be created")
        .project;
        let story = with_story.stories.last().expect("new story");
        assert_eq!(story.title, "Create");
        assert_eq!(story.number, 2);
        assert!(Uuid::parse_str(&story.id).is_ok());
        assert_eq!(story.acceptance_criteria[0].text, "Works");
    }

    #[test]
    fn attachment_limits_are_enforced_by_the_workspace_core() {
        let oversized = WorkspaceAttachment {
            id: "attachment".into(),
            filename: "large.bin".into(),
            content_type: "application/octet-stream".into(),
            byte_size: 50 * 1_024 * 1_024 + 1,
            sha256: "digest".into(),
            relative_path: "story/large.bin".into(),
            created_at: "2026-08-14T00:00:00Z".into(),
        };
        let error = apply_workspace_command(
            project(),
            WorkspaceCommand::AddAttachments {
                story_id: "story".into(),
                attachments: vec![oversized],
            },
        )
        .expect_err("attachment size must be limited");
        assert!(matches!(error, CoreError::WorkspaceAttachmentSizeLimit));
    }
}
