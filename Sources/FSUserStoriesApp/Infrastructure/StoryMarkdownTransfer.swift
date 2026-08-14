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

struct StoryMarkdownDocument: Codable, Equatable, Sendable {
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
        do {
            let result = try RustCoreClient().execute([
                "command": "export_markdown",
                "document": try encodedObject(document)
            ])
            guard let markdown = result["markdown"] as? String else {
                throw RustCoreError.invalidResponse
            }
            return markdown
        } catch let error as RustCoreError {
            throw mappedError(error)
        }
    }

    static func parse(_ markdown: String) throws -> StoryMarkdownDocument {
        do {
            let result = try RustCoreClient().execute([
                "command": "import_markdown",
                "markdown": markdown
            ])
            return try decodedDocument(result)
        } catch let error as RustCoreError {
            throw mappedError(error)
        }
    }

    private static func encodedObject(_ document: StoryMarkdownDocument) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let object = try JSONSerialization.jsonObject(with: encoder.encode(document))
        guard let dictionary = object as? [String: Any] else {
            throw RustCoreError.invalidResponse
        }
        return dictionary
    }

    private static func decodedDocument(_ object: [String: Any]) throws -> StoryMarkdownDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            StoryMarkdownDocument.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private static func mappedError(_ error: RustCoreError) -> Error {
        guard case let .coreFailure(code, _) = error else { return error }
        switch code {
        case "markdown_no_stories":
            return StoryMarkdownTransferError.noStories
        case "unsupported_markdown":
            return StoryMarkdownTransferError.unsupportedDocument
        case "invalid_markdown_story":
            return StoryMarkdownTransferError.invalidStory
        default:
            return error
        }
    }
}
