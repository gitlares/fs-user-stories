// SPDX-License-Identifier: MIT

import Foundation

struct StoryQuery {
    var projectID: UUID?
    var actorID: UUID?
    var status: StoryStatus?
    var text: String?
    var createdAfter: Date?
    var createdBefore: Date?
    var hasOpenCriteria: Bool?
}

extension AppStore {
    func stories(matching query: StoryQuery) -> [(project: FSProject, story: UserStory)] {
        let candidateProjects = query.projectID.map { projectID in
            projects.filter { $0.id == projectID }
        } ?? projects
        let normalizedText = query.text?.trimmingCharacters(in: .whitespacesAndNewlines)

        return candidateProjects.flatMap { project in
            project.stories.compactMap { story in
                guard query.actorID == nil || story.actorID == query.actorID else { return nil }
                guard query.status == nil || story.status == query.status else { return nil }
                guard query.createdAfter == nil || story.createdAt >= query.createdAfter! else { return nil }
                guard query.createdBefore == nil || story.createdAt <= query.createdBefore! else { return nil }
                if let hasOpenCriteria = query.hasOpenCriteria {
                    guard story.acceptanceCriteria.contains(where: { !$0.isMet }) == hasOpenCriteria else {
                        return nil
                    }
                }
                if let normalizedText, !normalizedText.isEmpty {
                    let actor = project.actors.first { $0.id == story.actorID }
                    let searchableText = [
                        story.title,
                        story.want,
                        story.outcome,
                        story.notes,
                        actor?.name ?? "",
                        actor?.role ?? "",
                        story.acceptanceCriteria.map(\.text).joined(separator: " ")
                    ].joined(separator: " ")
                    guard searchableText.localizedStandardContains(normalizedText) else { return nil }
                }
                return (project, story)
            }
        }
    }
}
