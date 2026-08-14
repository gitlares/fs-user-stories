// SPDX-License-Identifier: MIT

import Foundation

struct StoryQuery: Codable {
    var projectID: UUID?
    var actorID: UUID?
    var status: StoryStatus?
    var text: String?
    var createdAfter: Date?
    var createdBefore: Date?
    var hasOpenCriteria: Bool?
}

extension AppStore {
    /// Query semantics are owned by Rust so the UI and local MCP agree on
    /// status, text, date, profile, and open-criterion filtering.
    func stories(matching query: StoryQuery) -> [(project: FSProject, story: UserStory)] {
        guard let persistenceStore,
              let matches = try? persistenceStore.searchStories(matching: query) else {
            return []
        }
        return matches.map { ($0.project, $0.story) }
    }
}
