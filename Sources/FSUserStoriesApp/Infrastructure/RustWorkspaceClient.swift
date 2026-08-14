// SPDX-License-Identifier: MIT

import Foundation

struct RustWorkspaceClient: Sendable {
    func apply(project: FSProject, operation: [String: Any]) throws -> FSProject {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let projectData = try encoder.encode(project)
        guard let projectObject = try JSONSerialization.jsonObject(with: projectData) as? [String: Any] else {
            throw RustCoreError.invalidResponse
        }

        var command: [String: Any] = [
            "command": "apply_workspace_command",
            "project": projectObject
        ]
        operation.forEach { command[$0.key] = $0.value }

        let result = try RustCoreClient().execute(command)
        guard let updatedProject = result["project"] else {
            throw RustCoreError.invalidResponse
        }
        let resultData = try JSONSerialization.data(withJSONObject: updatedProject)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FSProject.self, from: resultData)
    }
}

struct RustWorkspaceDatabaseClient: Sendable {
    func createProject(name: String, prefix: String, databaseURL: URL) throws -> FSProject {
        let result = try RustCoreClient().execute([
            "command": "create_stored_project",
            "database_path": databaseURL.path,
            "name": name,
            "prefix": prefix
        ])
        guard let project = result["project"] else {
            throw RustCoreError.invalidResponse
        }
        return try decode(project, as: FSProject.self)
    }

    func deleteProject(
        projectID: UUID,
        databaseURL: URL,
        attachmentsRootURL: URL,
        repositoriesRootURL: URL
    ) throws {
        _ = try RustCoreClient().execute([
            "command": "delete_stored_project",
            "database_path": databaseURL.path,
            "attachments_root": attachmentsRootURL.path,
            "repositories_root": repositoriesRootURL.path,
            "project_id": projectID.uuidString
        ])
    }

    func deleteStory(
        storyID: UUID,
        projectID: UUID,
        databaseURL: URL,
        attachmentsRootURL: URL
    ) throws -> FSProject {
        let result = try RustCoreClient().execute([
            "command": "delete_stored_story",
            "database_path": databaseURL.path,
            "attachments_root": attachmentsRootURL.path,
            "project_id": projectID.uuidString,
            "story_id": storyID.uuidString
        ])
        guard let project = result["project"] else { throw RustCoreError.invalidResponse }
        return try decode(project, as: FSProject.self)
    }

    func loadProjects(databaseURL: URL) throws -> [FSProject] {
        let result = try RustCoreClient().execute([
            "command": "load_workspace",
            "database_path": databaseURL.path
        ])
        guard let projects = result["projects"] else {
            throw RustCoreError.invalidResponse
        }
        return try decode(projects, as: [FSProject].self)
    }

    func searchStories(
        matching query: StoryQuery,
        databaseURL: URL
    ) throws -> [RustWorkspaceStoryMatch] {
        let encodedQuery = try encode(query)
        let result = try RustCoreClient().execute([
            "command": "search_workspace",
            "database_path": databaseURL.path,
            "query": encodedQuery
        ])
        guard let matches = result["matches"] else {
            throw RustCoreError.invalidResponse
        }
        return try decode(matches, as: [RustWorkspaceStoryMatch].self)
    }

    func save(_ projects: [FSProject], databaseURL: URL) throws {
        let encodedProjects = try encode(projects)
        _ = try RustCoreClient().execute([
            "command": "save_workspace",
            "database_path": databaseURL.path,
            "projects": encodedProjects
        ])
    }

    func apply(
        projectID: UUID,
        operation: [String: Any],
        databaseURL: URL
    ) throws -> FSProject {
        var command: [String: Any] = [
            "command": "apply_stored_workspace_command",
            "database_path": databaseURL.path,
            "project_id": projectID.uuidString
        ]
        operation.forEach { command[$0.key] = $0.value }
        let result = try RustCoreClient().execute(command)
        guard let project = result["project"] else {
            throw RustCoreError.invalidResponse
        }
        return try decode(project, as: FSProject.self)
    }

    func importAttachments(
        sourceURLs: [URL],
        projectID: UUID,
        storyID: UUID,
        databaseURL: URL,
        attachmentsRootURL: URL
    ) throws -> FSProject {
        let result = try RustCoreClient().execute([
            "command": "import_stored_attachments",
            "database_path": databaseURL.path,
            "attachments_root": attachmentsRootURL.path,
            "project_id": projectID.uuidString,
            "story_id": storyID.uuidString,
            "source_paths": sourceURLs.map(\.path)
        ])
        guard let project = result["project"] else { throw RustCoreError.invalidResponse }
        return try decode(project, as: FSProject.self)
    }

    func removeAttachment(
        attachmentID: UUID,
        projectID: UUID,
        storyID: UUID,
        databaseURL: URL,
        attachmentsRootURL: URL
    ) throws -> FSProject {
        let result = try RustCoreClient().execute([
            "command": "remove_stored_attachment",
            "database_path": databaseURL.path,
            "attachments_root": attachmentsRootURL.path,
            "project_id": projectID.uuidString,
            "story_id": storyID.uuidString,
            "attachment_id": attachmentID.uuidString
        ])
        guard let project = result["project"] else { throw RustCoreError.invalidResponse }
        return try decode(project, as: FSProject.self)
    }

    private func encode<T: Encodable>(_ value: T) throws -> Any {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func decode<T: Decodable>(_ value: Any, as type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: value)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}

struct RustWorkspaceStoryMatch: Codable, Sendable {
    let project: FSProject
    let story: UserStory
}
