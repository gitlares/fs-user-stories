// SPDX-License-Identifier: MIT

use base64::{Engine as _, engine::general_purpose::STANDARD};
use serde::{Deserialize, Serialize};

use crate::protocol::CoreError;

const FORMAT_VERSION: u32 = 1;
const DATA_MARKER: &str = "<!-- fs-user-stories-data:";
const MARKER_END: &str = " -->";

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PortableAcceptanceCriterion {
    pub id: String,
    pub text: String,
    pub is_met: bool,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PortableStory {
    pub id: String,
    pub original_reference: String,
    pub title: String,
    pub profile_name: String,
    pub profile_description: String,
    pub want: String,
    pub outcome: String,
    pub notes: String,
    pub acceptance_criteria: Vec<PortableAcceptanceCriterion>,
    pub status: String,
    pub created_at: String,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StoryMarkdownDocument {
    pub project_name: String,
    pub project_prefix: String,
    pub stories: Vec<PortableStory>,
}

pub fn export_markdown(document: &StoryMarkdownDocument) -> Result<String, CoreError> {
    if document.stories.is_empty() {
        return Err(CoreError::MarkdownNoStories);
    }
    let sections = document
        .stories
        .iter()
        .map(story_markdown)
        .collect::<Result<Vec<_>, _>>()?
        .join("\n\n---\n\n");

    Ok(format!(
        "# {} — User Stories\n\n\
         > Exported by FS User Stories. Attachments are not included.\n\n\
         <!-- fs-user-stories-export:{FORMAT_VERSION} -->\n\n\
         {sections}",
        single_line(&document.project_name)
    ))
}

pub fn import_markdown(markdown: &str) -> Result<StoryMarkdownDocument, CoreError> {
    let version_marker = format!("<!-- fs-user-stories-export:{FORMAT_VERSION} -->");
    if !markdown.contains(&version_marker) {
        return Err(CoreError::UnsupportedMarkdown);
    }

    let stories = markdown
        .split(DATA_MARKER)
        .skip(1)
        .map(|remainder| {
            let payload = remainder
                .split_once(MARKER_END)
                .map(|(payload, _)| payload)
                .ok_or(CoreError::InvalidMarkdownStory)?;
            let data = STANDARD
                .decode(payload)
                .map_err(|_| CoreError::InvalidMarkdownStory)?;
            serde_json::from_slice(&data).map_err(|_| CoreError::InvalidMarkdownStory)
        })
        .collect::<Result<Vec<PortableStory>, CoreError>>()?;

    if stories.is_empty() {
        return Err(CoreError::UnsupportedMarkdown);
    }

    let title = markdown
        .split('\n')
        .find(|line| !line.is_empty())
        .unwrap_or_default();
    let project_name = title.replace("# ", "").replace(" — User Stories", "");
    let project_prefix = stories
        .first()
        .and_then(|story| story.original_reference.split('-').next())
        .unwrap_or_default()
        .to_owned();

    Ok(StoryMarkdownDocument {
        project_name,
        project_prefix,
        stories,
    })
}

fn story_markdown(story: &PortableStory) -> Result<String, CoreError> {
    // serde_json maps are key-sorted unless the preserve_order feature is enabled,
    // matching Swift's previous JSONEncoder.sortedKeys payload contract.
    let payload = STANDARD.encode(serde_json::to_vec(&serde_json::to_value(story)?)?);
    let criteria = story
        .acceptance_criteria
        .iter()
        .map(|criterion| {
            format!(
                "- [{}] {}",
                if criterion.is_met { "x" } else { " " },
                single_line(&criterion.text)
            )
        })
        .collect::<Vec<_>>()
        .join("\n");
    let criteria = if criteria.is_empty() {
        "No acceptance criteria."
    } else {
        &criteria
    };
    let notes = if story.notes.is_empty() {
        "No notes."
    } else {
        &story.notes
    };

    Ok(format!(
        "## {} — {}\n\n\
         {DATA_MARKER}{payload}{MARKER_END}\n\n\
         **Status:** {}  \n\
         **Profile:** {}\n\n\
         ### Story\n\n\
         **As:** {}  \n\
         **I want:** {}  \n\
         **So that:** {}\n\n\
         ### Acceptance Criteria\n\n\
         {criteria}\n\n\
         ### Notes\n\n\
         {notes}",
        single_line(&story.original_reference),
        single_line(&story.title),
        story.status,
        single_line(&story.profile_name),
        story.profile_name,
        story.want,
        story.outcome,
    ))
}

fn single_line(value: &str) -> String {
    value.replace('\n', " ")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn document() -> StoryMarkdownDocument {
        StoryMarkdownDocument {
            project_name: "Example".into(),
            project_prefix: "EX".into(),
            stories: vec![PortableStory {
                id: "C0971080-EBC9-4214-A55A-271B09439491".into(),
                original_reference: "EX-7".into(),
                title: "Export stories".into(),
                profile_name: "Developer".into(),
                profile_description: "Builds the product".into(),
                want: "one Markdown file".into(),
                outcome: "I can share the plan".into(),
                notes: "Keep it simple.".into(),
                acceptance_criteria: vec![PortableAcceptanceCriterion {
                    id: "1CF65DF4-1DCA-4AE6-93BD-D49AF90F91A6".into(),
                    text: "Exports criteria".into(),
                    is_met: true,
                }],
                status: "active".into(),
                created_at: "2023-11-14T22:13:20Z".into(),
            }],
        }
    }

    #[test]
    fn markdown_round_trip_preserves_portable_stories() {
        let source = document();
        let markdown = export_markdown(&source).expect("export should succeed");
        let imported = import_markdown(&markdown).expect("import should succeed");

        assert_eq!(imported, source);
        assert!(markdown.contains("## EX-7 — Export stories"));
        assert!(markdown.contains("- [x] Exports criteria"));
    }

    #[test]
    fn import_rejects_documents_without_the_version_marker() {
        let error = import_markdown("# Not an FS User Stories export")
            .expect_err("foreign Markdown must be rejected");
        assert!(matches!(error, CoreError::UnsupportedMarkdown));
    }
}
