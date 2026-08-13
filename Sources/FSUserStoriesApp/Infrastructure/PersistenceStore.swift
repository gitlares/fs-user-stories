// SPDX-License-Identifier: MIT

import Foundation
import SQLite3

enum PersistenceError: LocalizedError {
    case database(String)

    var errorDescription: String? {
        switch self {
        case let .database(message):
            "SQLite error: \(message)"
        }
    }
}

final class PersistenceStore {
    private var database: OpaquePointer?

    init(databaseURL: URL? = nil, isStoredInMemoryOnly: Bool = false) throws {
        let databasePath: String
        if isStoredInMemoryOnly {
            databasePath = ":memory:"
        } else {
            let url = try databaseURL ?? Self.defaultDatabaseURL()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            databasePath = url.path
        }

        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databasePath, &database, flags, nil) == SQLITE_OK else {
            let message = errorMessage
            sqlite3_close(database)
            database = nil
            throw PersistenceError.database(message)
        }

        try execute("PRAGMA foreign_keys = ON")
        if !isStoredInMemoryOnly {
            try execute("PRAGMA journal_mode = WAL")
        }
        try migrate()
    }

    deinit {
        sqlite3_close(database)
    }

    func loadProjects() throws -> [FSProject] {
        let statement = try prepare(
            """
            SELECT id, name, prefix, git_local_path, git_remote_url, git_default_branch,
                   git_last_synced_digest, git_last_synced_at
            FROM projects ORDER BY position
            """
        )
        defer { sqlite3_finalize(statement) }

        var projects: [FSProject] = []
        while try step(statement) {
            let projectID = try uuid(statement, column: 0)
            projects.append(
                FSProject(
                    id: projectID,
                    name: text(statement, column: 1),
                    prefix: text(statement, column: 2),
                    actors: try loadActors(projectID: projectID),
                    stories: try loadStories(projectID: projectID),
                    gitRepository: gitRepositoryLink(statement)
                )
            )
        }
        return projects
    }

    func save(_ projects: [FSProject]) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try execute("DELETE FROM projects")
            for (position, project) in projects.enumerated() {
                try insert(project, position: position)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
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

    private func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS projects (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                prefix TEXT NOT NULL,
                position INTEGER NOT NULL,
                git_bookmark BLOB,
                git_display_path TEXT,
                git_remote_name TEXT,
                git_local_path TEXT,
                git_remote_url TEXT,
                git_default_branch TEXT,
                git_last_synced_digest TEXT,
                git_last_synced_at REAL
            );

            CREATE TABLE IF NOT EXISTS actors (
                id TEXT PRIMARY KEY NOT NULL,
                project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                role TEXT NOT NULL,
                position INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS stories (
                id TEXT PRIMARY KEY NOT NULL,
                project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                number INTEGER NOT NULL,
                title TEXT NOT NULL,
                actor_id TEXT NOT NULL,
                want TEXT NOT NULL,
                outcome TEXT NOT NULL,
                notes TEXT NOT NULL DEFAULT '',
                status TEXT NOT NULL,
                created_at REAL NOT NULL,
                UNIQUE(project_id, number)
            );

            CREATE TABLE IF NOT EXISTS acceptance_criteria (
                id TEXT PRIMARY KEY NOT NULL,
                story_id TEXT NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
                text TEXT NOT NULL,
                is_met INTEGER NOT NULL,
                position INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS attachments (
                id TEXT PRIMARY KEY NOT NULL,
                story_id TEXT NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
                filename TEXT NOT NULL,
                content_type TEXT NOT NULL,
                byte_size INTEGER NOT NULL,
                sha256 TEXT NOT NULL,
                relative_path TEXT NOT NULL,
                created_at REAL NOT NULL,
                position INTEGER NOT NULL
            );

            """
        )

        if try !columnExists("notes", in: "stories") {
            try execute("ALTER TABLE stories ADD COLUMN notes TEXT NOT NULL DEFAULT ''")
        }
        if try !columnExists("git_bookmark", in: "projects") {
            try execute("ALTER TABLE projects ADD COLUMN git_bookmark BLOB")
            try execute("ALTER TABLE projects ADD COLUMN git_display_path TEXT")
            try execute("ALTER TABLE projects ADD COLUMN git_remote_name TEXT")
            try execute("ALTER TABLE projects ADD COLUMN git_last_synced_digest TEXT")
            try execute("ALTER TABLE projects ADD COLUMN git_last_synced_at REAL")
        }
        if try !columnExists("git_local_path", in: "projects") {
            try execute("ALTER TABLE projects ADD COLUMN git_local_path TEXT")
            try execute("ALTER TABLE projects ADD COLUMN git_remote_url TEXT")
            try execute("ALTER TABLE projects ADD COLUMN git_default_branch TEXT")
        }
        try execute("PRAGMA user_version = 5")
    }

    private func columnExists(_ column: String, in table: String) throws -> Bool {
        let statement = try prepare("PRAGMA table_info(\(table))")
        defer { sqlite3_finalize(statement) }

        while try step(statement) {
            if text(statement, column: 1) == column {
                return true
            }
        }
        return false
    }

    private func loadActors(projectID: UUID) throws -> [ProjectActor] {
        let statement = try prepare(
            "SELECT id, name, role FROM actors WHERE project_id = ? ORDER BY position"
        )
        defer { sqlite3_finalize(statement) }
        try bind(projectID.uuidString, to: 1, in: statement)

        var actors: [ProjectActor] = []
        while try step(statement) {
            actors.append(
                ProjectActor(
                    id: try uuid(statement, column: 0),
                    name: text(statement, column: 1),
                    role: text(statement, column: 2)
                )
            )
        }
        return actors
    }

    private func loadStories(projectID: UUID) throws -> [UserStory] {
        let statement = try prepare(
            """
            SELECT id, number, title, actor_id, want, outcome, status, notes, created_at
            FROM stories WHERE project_id = ? ORDER BY number
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(projectID.uuidString, to: 1, in: statement)

        var stories: [UserStory] = []
        while try step(statement) {
            let storyID = try uuid(statement, column: 0)
            stories.append(
                UserStory(
                    id: storyID,
                    number: Int(sqlite3_column_int64(statement, 1)),
                    title: text(statement, column: 2),
                    actorID: try uuid(statement, column: 3),
                    want: text(statement, column: 4),
                    outcome: text(statement, column: 5),
                    notes: text(statement, column: 7),
                    acceptanceCriteria: try loadCriteria(storyID: storyID),
                    attachments: try loadAttachments(storyID: storyID),
                    status: StoryStatus(rawValue: text(statement, column: 6)) ?? .draft,
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 8))
                )
            )
        }
        return stories
    }

    private func loadCriteria(storyID: UUID) throws -> [AcceptanceCriterion] {
        let statement = try prepare(
            """
            SELECT id, text, is_met FROM acceptance_criteria
            WHERE story_id = ? ORDER BY position
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(storyID.uuidString, to: 1, in: statement)

        var criteria: [AcceptanceCriterion] = []
        while try step(statement) {
            criteria.append(
                AcceptanceCriterion(
                    id: try uuid(statement, column: 0),
                    text: text(statement, column: 1),
                    isMet: sqlite3_column_int(statement, 2) == 1
                )
            )
        }
        return criteria
    }

    private func loadAttachments(storyID: UUID) throws -> [StoryAttachment] {
        let statement = try prepare(
            """
            SELECT id, filename, content_type, byte_size, sha256, relative_path, created_at
            FROM attachments WHERE story_id = ? ORDER BY position
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(storyID.uuidString, to: 1, in: statement)

        var attachments: [StoryAttachment] = []
        while try step(statement) {
            attachments.append(
                StoryAttachment(
                    id: try uuid(statement, column: 0),
                    filename: text(statement, column: 1),
                    contentType: text(statement, column: 2),
                    byteSize: sqlite3_column_int64(statement, 3),
                    sha256: text(statement, column: 4),
                    relativePath: text(statement, column: 5),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
                )
            )
        }
        return attachments
    }

    private func insert(_ project: FSProject, position: Int) throws {
        let statement = try prepare(
            """
            INSERT INTO projects
                (id, name, prefix, position, git_local_path, git_remote_url, git_default_branch,
                 git_last_synced_digest, git_last_synced_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(project.id.uuidString, to: 1, in: statement)
        try bind(project.name, to: 2, in: statement)
        try bind(project.prefix, to: 3, in: statement)
        sqlite3_bind_int64(statement, 4, Int64(position))
        if let link = project.gitRepository {
            try bind(link.localPath, to: 5, in: statement)
            try bind(link.remoteURL, to: 6, in: statement)
            try bind(link.defaultBranch, to: 7, in: statement)
            try bind(link.lastSyncedDigest, to: 8, in: statement)
            if let lastSyncedAt = link.lastSyncedAt {
                sqlite3_bind_double(statement, 9, lastSyncedAt.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(statement, 9)
            }
        } else {
            for index in 5...9 {
                sqlite3_bind_null(statement, Int32(index))
            }
        }
        try finish(statement)

        for (actorPosition, actor) in project.actors.enumerated() {
            try insert(actor, projectID: project.id, position: actorPosition)
        }
        for story in project.stories {
            try insert(story, projectID: project.id)
        }
    }

    private func insert(_ actor: ProjectActor, projectID: UUID, position: Int) throws {
        let statement = try prepare(
            """
            INSERT INTO actors (id, project_id, name, role, position)
            VALUES (?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(actor.id.uuidString, to: 1, in: statement)
        try bind(projectID.uuidString, to: 2, in: statement)
        try bind(actor.name, to: 3, in: statement)
        try bind(actor.role, to: 4, in: statement)
        sqlite3_bind_int64(statement, 5, Int64(position))
        try finish(statement)
    }

    private func insert(_ story: UserStory, projectID: UUID) throws {
        let statement = try prepare(
            """
            INSERT INTO stories
                (id, project_id, number, title, actor_id, want, outcome, status, notes, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(story.id.uuidString, to: 1, in: statement)
        try bind(projectID.uuidString, to: 2, in: statement)
        sqlite3_bind_int64(statement, 3, Int64(story.number))
        try bind(story.title, to: 4, in: statement)
        try bind(story.actorID.uuidString, to: 5, in: statement)
        try bind(story.want, to: 6, in: statement)
        try bind(story.outcome, to: 7, in: statement)
        try bind(story.status.rawValue, to: 8, in: statement)
        try bind(story.notes, to: 9, in: statement)
        sqlite3_bind_double(statement, 10, story.createdAt.timeIntervalSince1970)
        try finish(statement)

        for (position, criterion) in story.acceptanceCriteria.enumerated() {
            try insert(criterion, storyID: story.id, position: position)
        }
        for (position, attachment) in story.attachments.enumerated() {
            try insert(attachment, storyID: story.id, position: position)
        }
    }

    private func insert(
        _ criterion: AcceptanceCriterion,
        storyID: UUID,
        position: Int
    ) throws {
        let statement = try prepare(
            """
            INSERT INTO acceptance_criteria (id, story_id, text, is_met, position)
            VALUES (?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(criterion.id.uuidString, to: 1, in: statement)
        try bind(storyID.uuidString, to: 2, in: statement)
        try bind(criterion.text, to: 3, in: statement)
        sqlite3_bind_int(statement, 4, criterion.isMet ? 1 : 0)
        sqlite3_bind_int64(statement, 5, Int64(position))
        try finish(statement)
    }

    private func insert(
        _ attachment: StoryAttachment,
        storyID: UUID,
        position: Int
    ) throws {
        let statement = try prepare(
            """
            INSERT INTO attachments
                (id, story_id, filename, content_type, byte_size, sha256, relative_path, created_at, position)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(attachment.id.uuidString, to: 1, in: statement)
        try bind(storyID.uuidString, to: 2, in: statement)
        try bind(attachment.filename, to: 3, in: statement)
        try bind(attachment.contentType, to: 4, in: statement)
        sqlite3_bind_int64(statement, 5, attachment.byteSize)
        try bind(attachment.sha256, to: 6, in: statement)
        try bind(attachment.relativePath, to: 7, in: statement)
        sqlite3_bind_double(statement, 8, attachment.createdAt.timeIntervalSince1970)
        sqlite3_bind_int64(statement, 9, Int64(position))
        try finish(statement)
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw PersistenceError.database(errorMessage)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw PersistenceError.database(errorMessage)
        }
        return statement
    }

    private func bind(_ value: String, to index: Int32, in statement: OpaquePointer) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, index, value, -1, transient) == SQLITE_OK else {
            throw PersistenceError.database(errorMessage)
        }
    }

    private func bind(_ value: String?, to index: Int32, in statement: OpaquePointer) throws {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        try bind(value, to: index, in: statement)
    }

    private func bind(_ value: Data, to index: Int32, in statement: OpaquePointer) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let result = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), transient)
        }
        guard result == SQLITE_OK else {
            throw PersistenceError.database(errorMessage)
        }
    }

    private func gitRepositoryLink(_ statement: OpaquePointer) -> GitRepositoryLink? {
        guard let localPath = optionalText(statement, column: 3), !localPath.isEmpty else {
            return nil
        }
        return GitRepositoryLink(
            localPath: localPath,
            remoteURL: optionalText(statement, column: 4),
            defaultBranch: "fs-user-stories",
            lastSyncedDigest: optionalText(statement, column: 6),
            lastSyncedAt: sqlite3_column_type(statement, 7) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(statement, 7))
        )
    }

    private func optionalText(_ statement: OpaquePointer, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return text(statement, column: column)
    }

    private func step(_ statement: OpaquePointer) throws -> Bool {
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            true
        case SQLITE_DONE:
            false
        default:
            throw PersistenceError.database(errorMessage)
        }
    }

    private func finish(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw PersistenceError.database(errorMessage)
        }
    }

    private func text(_ statement: OpaquePointer, column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    private func uuid(_ statement: OpaquePointer, column: Int32) throws -> UUID {
        let value = text(statement, column: column)
        guard let id = UUID(uuidString: value) else {
            throw PersistenceError.database("Invalid UUID stored in the database")
        }
        return id
    }

    private var errorMessage: String {
        guard let database, let message = sqlite3_errmsg(database) else {
            return "Unknown database error"
        }
        return String(cString: message)
    }
}
