// SPDX-License-Identifier: MIT

use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::{archive::ProjectSnapshot, protocol::CoreError};

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncConflict {
    pub entity_type: String,
    pub entity_id: String,
    pub local: Option<Value>,
    pub shared: Option<Value>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MergeResult {
    pub merged: ProjectSnapshot,
    pub conflicts: Vec<SyncConflict>,
}

pub fn merge_snapshots(
    base: &ProjectSnapshot,
    local: &ProjectSnapshot,
    shared: &ProjectSnapshot,
) -> Result<MergeResult, CoreError> {
    base.validate()?;
    local.validate()?;
    shared.validate()?;
    if base.project_id != local.project_id || base.project_id != shared.project_id {
        return Err(CoreError::ProjectMismatch);
    }

    let (actors, mut conflicts) =
        merge_entities("profile", &base.actors, &local.actors, &shared.actors)?;
    let (mut stories, story_conflicts) =
        merge_entities("story", &base.stories, &local.stories, &shared.stories)?;
    normalize_story_numbers(&mut stories)?;
    conflicts.extend(story_conflicts);

    let header_local_changed = project_header(local) != project_header(base);
    let header_shared_changed = project_header(shared) != project_header(base);
    let header = if !header_local_changed && header_shared_changed {
        shared
    } else {
        local
    };
    if header_local_changed
        && header_shared_changed
        && project_header(local) != project_header(shared)
    {
        conflicts.push(SyncConflict {
            entity_type: "project".into(),
            entity_id: base.project_id.clone(),
            local: Some(project_header(local)),
            shared: Some(project_header(shared)),
        });
    }

    Ok(MergeResult {
        merged: ProjectSnapshot {
            format_version: ProjectSnapshot::FORMAT_VERSION,
            project_id: header.project_id.clone(),
            name: header.name.clone(),
            prefix: header.prefix.clone(),
            actors,
            stories,
        },
        conflicts,
    })
}

pub fn apply_resolutions(
    mut result: MergeResult,
    resolutions: &[ConflictResolution],
) -> Result<ProjectSnapshot, CoreError> {
    let choices = resolutions
        .iter()
        .map(|item| {
            (
                (item.entity_type.as_str(), item.entity_id.as_str()),
                item.choice,
            )
        })
        .collect::<BTreeMap<_, _>>();
    for conflict in &result.conflicts {
        let choice = choices
            .get(&(conflict.entity_type.as_str(), conflict.entity_id.as_str()))
            .ok_or_else(|| CoreError::UnresolvedConflict(conflict.entity_id.clone()))?;
        let value = match choice {
            ResolutionChoice::Mine => conflict.local.clone(),
            ResolutionChoice::Shared => conflict.shared.clone(),
        };
        match conflict.entity_type.as_str() {
            "project" => {
                if let Some(value) = value {
                    result.merged.name = required_string(&value, "name")?;
                    result.merged.prefix = required_string(&value, "prefix")?;
                }
            }
            "profile" => replace_entity(&mut result.merged.actors, &conflict.entity_id, value)?,
            "story" => replace_entity(&mut result.merged.stories, &conflict.entity_id, value)?,
            _ => return Err(CoreError::InvalidArchive("Unknown conflict type".into())),
        }
    }
    normalize_story_numbers(&mut result.merged.stories)?;
    result.merged.validate()?;
    Ok(result.merged)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ResolutionChoice {
    Mine,
    Shared,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConflictResolution {
    pub entity_type: String,
    pub entity_id: String,
    pub choice: ResolutionChoice,
}

fn merge_entities(
    entity_type: &str,
    base: &[Value],
    local: &[Value],
    shared: &[Value],
) -> Result<(Vec<Value>, Vec<SyncConflict>), CoreError> {
    let base = entity_map(base)?;
    let local = entity_map(local)?;
    let shared = entity_map(shared)?;
    let ids = base
        .keys()
        .chain(local.keys())
        .chain(shared.keys())
        .cloned()
        .collect::<BTreeSet<_>>();
    let mut merged = Vec::new();
    let mut conflicts = Vec::new();

    for id in ids {
        let base_value = base.get(&id).copied();
        let local_value = local.get(&id).copied();
        let shared_value = shared.get(&id).copied();
        let local_changed = local_value != base_value;
        let shared_changed = shared_value != base_value;
        let selected = match (local_changed, shared_changed) {
            (false, false) | (true, false) => local_value,
            (false, true) => shared_value,
            (true, true) if local_value == shared_value => local_value,
            (true, true) => {
                conflicts.push(SyncConflict {
                    entity_type: entity_type.into(),
                    entity_id: id.clone(),
                    local: local_value.cloned(),
                    shared: shared_value.cloned(),
                });
                local_value
            }
        };
        if let Some(value) = selected {
            merged.push(value.clone());
        }
    }
    Ok((merged, conflicts))
}

fn entity_map(values: &[Value]) -> Result<BTreeMap<String, &Value>, CoreError> {
    values
        .iter()
        .map(|value| {
            let id = required_string(value, "id")?;
            Ok((id, value))
        })
        .collect()
}

fn normalize_story_numbers(stories: &mut [Value]) -> Result<(), CoreError> {
    let mut numbered_stories = stories
        .iter()
        .enumerate()
        .filter_map(|(index, story)| {
            let number = story.get("number")?.as_u64()?;
            let id = story.get("id")?.as_str()?.to_owned();
            let created_at = story
                .get("createdAt")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_owned();
            Some((index, number, created_at, id))
        })
        .collect::<Vec<_>>();

    numbered_stories
        .sort_by(|left, right| (left.1, &left.2, &left.3).cmp(&(right.1, &right.2, &right.3)));
    let mut used = BTreeSet::new();
    let mut duplicates = Vec::new();
    for (index, number, _, _) in &numbered_stories {
        if !used.insert(*number) {
            duplicates.push(*index);
        }
    }

    let mut next_number = numbered_stories
        .iter()
        .map(|(_, number, _, _)| *number)
        .max()
        .unwrap_or(0)
        .checked_add(1)
        .ok_or_else(|| CoreError::InvalidArchive("Story number limit reached".into()))?;
    for index in duplicates {
        while used.contains(&next_number) {
            next_number = next_number
                .checked_add(1)
                .ok_or_else(|| CoreError::InvalidArchive("Story number limit reached".into()))?;
        }
        let story = stories[index]
            .as_object_mut()
            .ok_or_else(|| CoreError::InvalidArchive("Story must be an object".into()))?;
        story.insert("number".into(), Value::from(next_number));
        used.insert(next_number);
        next_number = next_number
            .checked_add(1)
            .ok_or_else(|| CoreError::InvalidArchive("Story number limit reached".into()))?;
    }
    Ok(())
}

fn project_header(snapshot: &ProjectSnapshot) -> Value {
    serde_json::json!({"name": snapshot.name, "prefix": snapshot.prefix})
}

fn required_string(value: &Value, key: &str) -> Result<String, CoreError> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(str::to_owned)
        .ok_or_else(|| CoreError::InvalidArchive(format!("Missing {key}")))
}

fn replace_entity(
    entities: &mut Vec<Value>,
    entity_id: &str,
    replacement: Option<Value>,
) -> Result<(), CoreError> {
    entities.retain(|value| {
        required_string(value, "id")
            .map(|id| id != entity_id)
            .unwrap_or(true)
    });
    if let Some(value) = replacement {
        entities.push(value);
    }
    entities.sort_by_key(|value| required_string(value, "id").unwrap_or_default());
    Ok(())
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    fn snapshot(actors: Vec<Value>, stories: Vec<Value>) -> ProjectSnapshot {
        ProjectSnapshot {
            format_version: 1,
            project_id: "project".into(),
            name: "Example".into(),
            prefix: "EX".into(),
            actors,
            stories,
        }
    }

    #[test]
    fn merges_changes_to_different_entities_without_conflict() {
        let base = snapshot(
            vec![json!({"id":"a", "name":"Developer"})],
            vec![json!({"id":"s", "title":"Old"})],
        );
        let local = snapshot(
            vec![json!({"id":"a", "name":"Engineer"})],
            base.stories.clone(),
        );
        let shared = snapshot(base.actors.clone(), vec![json!({"id":"s", "title":"New"})]);
        let result = merge_snapshots(&base, &local, &shared).unwrap();
        assert!(result.conflicts.is_empty());
        assert_eq!(result.merged.actors, local.actors);
        assert_eq!(result.merged.stories, shared.stories);
    }

    #[test]
    fn reports_same_entity_conflict_and_applies_choice() {
        let base = snapshot(vec![], vec![json!({"id":"s", "title":"Old"})]);
        let local = snapshot(vec![], vec![json!({"id":"s", "title":"Mine"})]);
        let shared = snapshot(vec![], vec![json!({"id":"s", "title":"Shared"})]);
        let result = merge_snapshots(&base, &local, &shared).unwrap();
        assert_eq!(result.conflicts.len(), 1);
        let merged = apply_resolutions(
            result,
            &[ConflictResolution {
                entity_type: "story".into(),
                entity_id: "s".into(),
                choice: ResolutionChoice::Shared,
            }],
        )
        .unwrap();
        assert_eq!(merged.stories[0]["title"], "Shared");
    }

    #[test]
    fn concurrent_stories_keep_distinct_uuids_and_receive_unique_numbers() {
        let base = snapshot(
            vec![],
            vec![json!({
                "id":"00000000-0000-0000-0000-000000000001",
                "number":1,
                "createdAt":"2026-08-13T10:00:00Z",
                "title":"Existing"
            })],
        );
        let mut local_stories = base.stories.clone();
        local_stories.push(json!({
            "id":"00000000-0000-0000-0000-000000000002",
            "number":2,
            "createdAt":"2026-08-13T11:00:00Z",
            "title":"Created on Mac A"
        }));
        let mut shared_stories = base.stories.clone();
        shared_stories.push(json!({
            "id":"00000000-0000-0000-0000-000000000003",
            "number":2,
            "createdAt":"2026-08-13T11:00:01Z",
            "title":"Created on Mac B"
        }));

        let result = merge_snapshots(
            &base,
            &snapshot(vec![], local_stories),
            &snapshot(vec![], shared_stories),
        )
        .unwrap();

        assert!(result.conflicts.is_empty());
        let ids = result
            .merged
            .stories
            .iter()
            .map(|story| story["id"].as_str().unwrap())
            .collect::<BTreeSet<_>>();
        let numbers = result
            .merged
            .stories
            .iter()
            .map(|story| story["number"].as_u64().unwrap())
            .collect::<BTreeSet<_>>();
        assert_eq!(ids.len(), 3);
        assert_eq!(numbers, BTreeSet::from([1, 2, 3]));
    }
}
