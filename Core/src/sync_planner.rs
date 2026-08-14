// SPDX-License-Identifier: MIT

//! Pure synchronization policy; Swift supplies clocks and executes I/O only.
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncPlannerPolicy {
    pub debounce: f64,
    pub maximum_delay: f64,
    pub active_delay: f64,
    pub active_refresh: f64,
    pub inactive_refresh: f64,
    pub retries: Vec<f64>,
}
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncPlannerState {
    #[serde(default)]
    pub first_changes: BTreeMap<String, f64>,
    #[serde(default)]
    pub failures: BTreeMap<String, usize>,
    #[serde(default)]
    pub cursor: usize,
}
#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncProject {
    pub id: String,
    pub remote: bool,
    pub last_synced: Option<f64>,
}
#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncPlannerRequest {
    pub policy: SyncPlannerPolicy,
    pub state: SyncPlannerState,
    pub projects: Vec<SyncProject>,
    pub active_id: Option<String>,
    pub now: f64,
    pub event: String,
    pub project_id: Option<String>,
    pub succeeded: Option<bool>,
    pub blocked: Option<bool>,
}
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncPlannerDecision {
    pub state: SyncPlannerState,
    pub schedules: Vec<SyncSchedule>,
}
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncSchedule {
    pub project_id: String,
    pub delay: f64,
}

pub fn plan(mut value: SyncPlannerRequest) -> SyncPlannerDecision {
    let mut schedules = vec![];
    let due = |p: &SyncProject, interval: f64| {
        p.remote && p.last_synced.is_none_or(|at| value.now - at >= interval)
    };
    match value.event.as_str() {
        "local_change" => {
            if let Some(id) = value.project_id {
                let first = *value
                    .state
                    .first_changes
                    .entry(id.clone())
                    .or_insert(value.now);
                schedules.push(SyncSchedule {
                    project_id: id,
                    delay: value
                        .policy
                        .debounce
                        .min((value.policy.maximum_delay - (value.now - first)).max(0.0)),
                });
            }
        }
        "immediate" => {
            if let Some(id) = value.project_id {
                schedules.push(SyncSchedule {
                    project_id: id,
                    delay: 0.0,
                });
            }
        }
        "active" => {
            if let Some(id) = value.project_id
                && value
                    .projects
                    .iter()
                    .find(|p| p.id == id)
                    .is_some_and(|p| due(p, value.policy.active_refresh))
            {
                schedules.push(SyncSchedule {
                    project_id: id,
                    delay: value.policy.active_delay,
                });
            }
        }
        "maintenance" => {
            if let Some(id) = value.active_id.clone()
                && value
                    .projects
                    .iter()
                    .find(|p| p.id == id)
                    .is_some_and(|p| due(p, value.policy.active_refresh))
            {
                schedules.push(SyncSchedule {
                    project_id: id,
                    delay: value.policy.active_delay,
                });
            }
            let eligible = value
                .projects
                .iter()
                .filter(|p| {
                    Some(&p.id) != value.active_id.as_ref() && due(p, value.policy.inactive_refresh)
                })
                .collect::<Vec<_>>();
            if !eligible.is_empty() {
                let p = eligible[value.state.cursor % eligible.len()];
                value.state.cursor = (value.state.cursor + 1) % eligible.len();
                schedules.push(SyncSchedule {
                    project_id: p.id.clone(),
                    delay: 0.0,
                });
            }
        }
        "finished" => {
            if let Some(id) = value.project_id {
                value.state.first_changes.remove(&id);
                if value.blocked == Some(true) || value.succeeded == Some(true) {
                    value.state.failures.remove(&id);
                } else {
                    let f = value.state.failures.entry(id.clone()).or_default();
                    let delay = value.policy.retries
                        [(*f).min(value.policy.retries.len().saturating_sub(1))];
                    *f += 1;
                    schedules.push(SyncSchedule {
                        project_id: id,
                        delay,
                    });
                }
            }
        }
        _ => {}
    };
    SyncPlannerDecision {
        state: value.state,
        schedules,
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn edit_cap() {
        let p = SyncPlannerPolicy {
            debounce: 3.,
            maximum_delay: 15.,
            active_delay: 1.,
            active_refresh: 30.,
            inactive_refresh: 1800.,
            retries: vec![60.],
        };
        let a = plan(SyncPlannerRequest {
            policy: p.clone(),
            state: Default::default(),
            projects: vec![],
            active_id: None,
            now: 0.,
            event: "local_change".into(),
            project_id: Some("p".into()),
            succeeded: None,
            blocked: None,
        });
        let b = plan(SyncPlannerRequest {
            policy: p,
            state: a.state,
            projects: vec![],
            active_id: None,
            now: 14.,
            event: "local_change".into(),
            project_id: Some("p".into()),
            succeeded: None,
            blocked: None,
        });
        assert_eq!(b.schedules[0].delay, 1.);
    }
}
