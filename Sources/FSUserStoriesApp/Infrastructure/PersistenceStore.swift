// SPDX-License-Identifier: MIT

import Foundation

enum PersistenceError: LocalizedError {
    case database(String)

    var errorDescription: String? {
        switch self {
        case let .database(message):
            "SQLite error: \(message)"
        }
    }
}

/// The sole SQLite database is owned, migrated, and accessed by the Rust core.
/// Swift only supplies the macOS-standard location and decodes view models.
final class PersistenceStore {
    let databaseURL: URL
    private let removesDatabaseOnDeinit: Bool

    init(databaseURL: URL? = nil, isStoredInMemoryOnly: Bool = false) throws {
        if isStoredInMemoryOnly {
            self.databaseURL = FileManager.default.temporaryDirectory
                .appending(path: "FSUserStories-\(UUID().uuidString).sqlite3")
            self.removesDatabaseOnDeinit = true
        } else {
            self.databaseURL = try databaseURL ?? Self.defaultDatabaseURL()
            self.removesDatabaseOnDeinit = false
        }
        try FileManager.default.createDirectory(
            at: self.databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    deinit {
        guard removesDatabaseOnDeinit else { return }
        try? FileManager.default.removeItem(at: databaseURL)
        try? FileManager.default.removeItem(atPath: databaseURL.path + "-shm")
        try? FileManager.default.removeItem(atPath: databaseURL.path + "-wal")
    }

    func loadProjects() throws -> [FSProject] {
        try RustWorkspaceDatabaseClient().loadProjects(
            databaseURL: databaseURL,
            attachmentsRootURL: Self.defaultAttachmentsRootURL()
        )
    }

    func searchStories(matching query: StoryQuery) throws -> [RustWorkspaceStoryMatch] {
        try RustWorkspaceDatabaseClient().searchStories(matching: query, databaseURL: databaseURL)
    }

    func save(_ projects: [FSProject]) throws {
        try RustWorkspaceDatabaseClient().save(projects, databaseURL: databaseURL)
    }

    func createProject(name: String, prefix: String) throws -> FSProject {
        try RustWorkspaceDatabaseClient().createProject(
            name: name,
            prefix: prefix,
            databaseURL: databaseURL
        )
    }

    func deleteProject(
        _ projectID: UUID,
        attachmentsRootURL: URL,
        repositoriesRootURL: URL
    ) throws {
        try RustWorkspaceDatabaseClient().deleteProject(
            projectID: projectID,
            databaseURL: databaseURL,
            attachmentsRootURL: attachmentsRootURL,
            repositoriesRootURL: repositoriesRootURL
        )
    }

    func deleteStory(
        _ storyID: UUID,
        projectID: UUID,
        attachmentsRootURL: URL
    ) throws -> FSProject {
        try RustWorkspaceDatabaseClient().deleteStory(
            storyID: storyID,
            projectID: projectID,
            databaseURL: databaseURL,
            attachmentsRootURL: attachmentsRootURL
        )
    }

    func applyWorkspaceOperation(
        projectID: UUID,
        operation: [String: Any]
    ) throws -> FSProject {
        try RustWorkspaceDatabaseClient().apply(
            projectID: projectID,
            operation: operation,
            databaseURL: databaseURL
        )
    }

    func importAttachments(
        sourceURLs: [URL],
        projectID: UUID,
        storyID: UUID,
        attachmentsRootURL: URL
    ) throws -> FSProject {
        try RustWorkspaceDatabaseClient().importAttachments(
            sourceURLs: sourceURLs,
            projectID: projectID,
            storyID: storyID,
            databaseURL: databaseURL,
            attachmentsRootURL: attachmentsRootURL
        )
    }

    func removeAttachment(
        attachmentID: UUID,
        projectID: UUID,
        storyID: UUID,
        attachmentsRootURL: URL
    ) throws -> FSProject {
        try RustWorkspaceDatabaseClient().removeAttachment(
            attachmentID: attachmentID,
            projectID: projectID,
            storyID: storyID,
            databaseURL: databaseURL,
            attachmentsRootURL: attachmentsRootURL
        )
    }

    private static func defaultDatabaseURL() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport
            .appending(path: "FS User Stories", directoryHint: .isDirectory)
            .appending(path: "FSUserStories.sqlite3", directoryHint: .notDirectory)
    }

    private static func defaultAttachmentsRootURL() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = applicationSupport
            .appending(path: "FS User Stories", directoryHint: .isDirectory)
            .appending(path: "Attachments", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
