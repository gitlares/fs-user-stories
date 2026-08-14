// SPDX-License-Identifier: MIT

import Foundation

struct PortableStory: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var originalReference: String
    var title: String
    var profileName: String
    var profileDescription: String
    var want: String
    var outcome: String
    var notes: String
    var acceptanceCriteria: [AcceptanceCriterion]
    var status: StoryStatus
    var createdAt: Date
}

struct StoryMarkdownDocument: Equatable, Sendable {
    static let formatVersion = 1

    var projectName: String
    var projectPrefix: String
    var stories: [PortableStory]
}

enum StoryMarkdownTransferError: LocalizedError {
    case noStories
    case unsupportedDocument
    case invalidStory

    var errorDescription: String? {
        switch self {
        case .noStories:
            L10n.string("Choose at least one story.")
        case .unsupportedDocument:
            L10n.string("This Markdown file was not exported by FS User Stories.")
        case .invalidStory:
            L10n.string("The Markdown file contains a story that could not be read.")
        }
    }
}

enum StoryMarkdownTransfer {
    private static let dataMarker = "<!-- fs-user-stories-data:"
    private static let markerEnd = " -->"

    static func document(project: FSProject, storyIDs: Set<UUID>) throws -> StoryMarkdownDocument {
        let stories = project.stories
            .filter { storyIDs.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
            .map { story in
                let profile = project.actors.first { $0.id == story.actorID }
                return PortableStory(
                    id: story.id,
                    originalReference: "\(project.prefix)-\(story.number)",
                    title: story.title,
                    profileName: profile?.name ?? L10n.string("Unknown actor"),
                    profileDescription: profile?.role ?? "",
                    want: story.want,
                    outcome: story.outcome,
                    notes: story.notes,
                    acceptanceCriteria: story.acceptanceCriteria,
                    status: story.status,
                    createdAt: story.createdAt
                )
            }
        guard !stories.isEmpty else { throw StoryMarkdownTransferError.noStories }
        return StoryMarkdownDocument(
            projectName: project.name,
            projectPrefix: project.prefix,
            stories: stories
        )
    }

    static func markdown(for document: StoryMarkdownDocument) throws -> String {
        let storySections = try document.stories.map(storyMarkdown).joined(separator: "\n\n---\n\n")
        return """
        # \(singleLine(document.projectName)) — User Stories

        > Exported by FS User Stories. Attachments are not included.

        <!-- fs-user-stories-export:\(StoryMarkdownDocument.formatVersion) -->

        \(storySections)
        """
    }

    static func parse(_ markdown: String) throws -> StoryMarkdownDocument {
        guard markdown.contains("<!-- fs-user-stories-export:\(StoryMarkdownDocument.formatVersion) -->") else {
            throw StoryMarkdownTransferError.unsupportedDocument
        }

        let payloads = markdown.components(separatedBy: dataMarker).dropFirst().compactMap { remainder -> String? in
            remainder.components(separatedBy: markerEnd).first
        }
        guard !payloads.isEmpty else { throw StoryMarkdownTransferError.unsupportedDocument }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let stories = try payloads.map { payload -> PortableStory in
            guard let data = Data(base64Encoded: payload) else {
                throw StoryMarkdownTransferError.invalidStory
            }
            do {
                return try decoder.decode(PortableStory.self, from: data)
            } catch {
                throw StoryMarkdownTransferError.invalidStory
            }
        }

        let title = markdown.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        let projectName = title
            .replacingOccurrences(of: "# ", with: "")
            .replacingOccurrences(of: " — User Stories", with: "")
        let prefix = stories.first?.originalReference.split(separator: "-").first.map(String.init) ?? ""
        return StoryMarkdownDocument(projectName: projectName, projectPrefix: prefix, stories: stories)
    }

    private static func storyMarkdown(_ story: PortableStory) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(story).base64EncodedString()
        let criteria = story.acceptanceCriteria.map { criterion in
            "- [\(criterion.isMet ? "x" : " ")] \(singleLine(criterion.text))"
        }.joined(separator: "\n")

        return """
        ## \(singleLine(story.originalReference)) — \(singleLine(story.title))

        \(dataMarker)\(payload)\(markerEnd)

        **Status:** \(story.status.rawValue)  
        **Profile:** \(singleLine(story.profileName))

        ### Story

        **As:** \(story.profileName)  
        **I want:** \(story.want)  
        **So that:** \(story.outcome)

        ### Acceptance Criteria

        \(criteria.isEmpty ? "No acceptance criteria." : criteria)

        ### Notes

        \(story.notes.isEmpty ? "No notes." : story.notes)
        """
    }

    private static func singleLine(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: " ")
    }
}
