// SPDX-License-Identifier: MIT

import CryptoKit
import Foundation

enum GitArchiveError: LocalizedError {
    case archiveNotFound
    case unsupportedVersion(Int)
    case projectMismatch
    case attachmentMissing(String)

    var errorDescription: String? {
        switch self {
        case .archiveNotFound: "This repository does not contain an FS User Stories archive."
        case let .unsupportedVersion(version): "Archive version \(version) is not supported."
        case .projectMismatch: "The repository archive belongs to a different project."
        case let .attachmentMissing(filename): "The synchronized attachment is missing: \(filename)"
        }
    }
}

struct GitProjectSnapshot: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var projectID: UUID
    var name: String
    var prefix: String
    var actors: [Actor]
    var stories: [Story]

    struct Actor: Codable, Equatable, Sendable {
        var id: UUID
        var name: String
        var role: String
    }

    struct Story: Codable, Equatable, Sendable {
        var id: UUID
        var number: Int
        var title: String
        var actorID: UUID
        var want: String
        var outcome: String
        var notes: String
        var acceptanceCriteria: [Criterion]
        var attachments: [Attachment]
        var status: String
        var createdAt: Date
    }

    struct Criterion: Codable, Equatable, Sendable {
        var id: UUID
        var text: String
        var isMet: Bool
    }

    struct Attachment: Codable, Equatable, Sendable {
        var id: UUID
        var filename: String
        var contentType: String
        var byteSize: Int64
        var sha256: String
        var archiveRelativePath: String
        var createdAt: Date
    }
}

struct GitProjectArchive {
    static let directoryName = ".fs-user-stories"
    static let snapshotFilename = "project.json"

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func snapshot(for project: FSProject) -> GitProjectSnapshot {
        GitProjectSnapshot(
            formatVersion: GitProjectSnapshot.currentFormatVersion,
            projectID: project.id,
            name: project.name,
            prefix: project.prefix,
            actors: project.actors.map {
                .init(id: $0.id, name: $0.name, role: $0.role)
            },
            stories: project.stories.map { story in
                .init(
                    id: story.id,
                    number: story.number,
                    title: story.title,
                    actorID: story.actorID,
                    want: story.want,
                    outcome: story.outcome,
                    notes: story.notes,
                    acceptanceCriteria: story.acceptanceCriteria.map {
                        .init(id: $0.id, text: $0.text, isMet: $0.isMet)
                    },
                    attachments: story.attachments.map { attachment in
                        .init(
                            id: attachment.id,
                            filename: attachment.filename,
                            contentType: attachment.contentType,
                            byteSize: attachment.byteSize,
                            sha256: attachment.sha256,
                            archiveRelativePath: attachmentArchivePath(
                                storyID: story.id,
                                attachment: attachment
                            ),
                            createdAt: attachment.createdAt
                        )
                    },
                    status: story.status.rawValue,
                    createdAt: story.createdAt
                )
            }
        )
    }

    func digest(for project: FSProject) throws -> String {
        try digest(for: snapshot(for: project))
    }

    func digest(for snapshot: GitProjectSnapshot) throws -> String {
        SHA256.hash(data: try encoder.encode(snapshot))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    @discardableResult
    func write(
        _ project: FSProject,
        to repositoryURL: URL,
        attachmentURL: (StoryAttachment) -> URL?
    ) throws -> String {
        let snapshot = snapshot(for: project)
        let stagingURL = repositoryURL.appending(
            path: "\(Self.directoryName).tmp-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: stagingURL) }
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        try encoder.encode(snapshot).write(
            to: stagingURL.appending(path: Self.snapshotFilename),
            options: .atomic
        )
        try projectReadme(project, snapshot: snapshot).write(
            to: stagingURL.appending(path: "README.md"),
            atomically: true,
            encoding: .utf8
        )

        let storiesURL = stagingURL.appending(path: "stories", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: storiesURL, withIntermediateDirectories: true)
        for story in project.stories {
            let filename = "\(project.prefix)-\(story.number)-\(slug(story.title)).md"
            try storyMarkdown(story, project: project).write(
                to: storiesURL.appending(path: filename),
                atomically: true,
                encoding: .utf8
            )
            for attachment in story.attachments {
                guard let sourceURL = attachmentURL(attachment),
                      fileManager.fileExists(atPath: sourceURL.path) else {
                    throw GitArchiveError.attachmentMissing(attachment.filename)
                }
                let destinationURL = stagingURL.appending(
                    path: attachmentArchivePath(storyID: story.id, attachment: attachment)
                )
                try fileManager.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }
        }

        let archiveURL = repositoryURL.appending(path: Self.directoryName, directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }
        try fileManager.moveItem(at: stagingURL, to: archiveURL)
        return try digest(for: snapshot)
    }

    func read(from repositoryURL: URL) throws -> GitProjectSnapshot {
        let snapshotURL = repositoryURL
            .appending(path: Self.directoryName, directoryHint: .isDirectory)
            .appending(path: Self.snapshotFilename)
        guard fileManager.fileExists(atPath: snapshotURL.path) else {
            throw GitArchiveError.archiveNotFound
        }
        let snapshot = try decoder.decode(GitProjectSnapshot.self, from: Data(contentsOf: snapshotURL))
        guard snapshot.formatVersion == GitProjectSnapshot.currentFormatVersion else {
            throw GitArchiveError.unsupportedVersion(snapshot.formatVersion)
        }
        return snapshot
    }

    func archivePath(storyID: UUID, attachment: StoryAttachment) -> String {
        attachmentArchivePath(storyID: storyID, attachment: attachment)
    }

    private func attachmentArchivePath(
        storyID: UUID,
        attachment: StoryAttachment
    ) -> String {
        "attachments/\(storyID.uuidString)/\(attachment.id.uuidString)-\(safeFilename(attachment.filename))"
    }

    private func projectReadme(_ project: FSProject, snapshot: GitProjectSnapshot) -> String {
        let completed = snapshot.stories.count { $0.status == StoryStatus.done.rawValue }
        return """
        # \(project.name)

        FS User Stories project archive.

        - Prefix: `\(project.prefix)`
        - Profiles: \(project.actors.count)
        - Stories: \(project.stories.count)
        - Completed: \(completed)/\(project.stories.count)

        Human-readable stories are in `stories/`. `project.json` is the synchronized source of truth.
        """
    }

    private func storyMarkdown(_ story: UserStory, project: FSProject) -> String {
        let actor = project.actors.first { $0.id == story.actorID }
        let criteria = story.acceptanceCriteria.map {
            "- [\($0.isMet ? "x" : " ")] \($0.text)"
        }.joined(separator: "\n")
        let attachments = story.attachments.map {
            "- [\($0.filename)](../\(attachmentArchivePath(storyID: story.id, attachment: $0)))"
        }.joined(separator: "\n")
        return """
        # \(project.prefix)-\(story.number) — \(story.title)

        **Status:** \(story.status.rawValue)  
        **Profile:** \(actor?.name ?? "Unknown")

        ## Story

        As **\(actor?.name ?? "Unknown")**, I want **\(story.want)**, so that **\(story.outcome)**.

        ## Acceptance criteria

        \(criteria.isEmpty ? "No acceptance criteria." : criteria)

        ## Notes

        \(story.notes.isEmpty ? "No notes." : story.notes)

        ## Attachments

        \(attachments.isEmpty ? "No attachments." : attachments)
        """
    }

    private func slug(_ value: String) -> String {
        let words = value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        let result = words.filter { !$0.isEmpty }.joined(separator: "-")
        return result.isEmpty ? "story" : String(result.prefix(60))
    }

    private func safeFilename(_ value: String) -> String {
        value.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }
}
