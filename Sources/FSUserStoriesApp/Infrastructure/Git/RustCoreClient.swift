// SPDX-License-Identifier: MIT

import Foundation

enum RustCoreError: LocalizedError {
    case executableMissing
    case invalidResponse
    case commandFailed(String)
    case coreFailure(code: String, message: String)
    case syncConflicts([CoreSyncConflict])

    var errorDescription: String? {
        switch self {
        case .executableMissing:
            "The bundled FS User Stories core is missing."
        case .invalidResponse:
            "The FS User Stories core returned an invalid response."
        case let .commandFailed(message):
            message
        case let .coreFailure(_, message):
            message
        case .syncConflicts:
            L10n.string("Some shared changes need your decision.")
        }
    }
}

struct RustCoreClient: Sendable {
    let executableURL: URL

    init(executableURL: URL? = nil) throws {
        if let executableURL {
            self.executableURL = executableURL
            return
        }
        let bundledURL = AppResources.bundle.url(
            forResource: "fs-user-stories-core",
            withExtension: nil,
            subdirectory: "Core"
        ) ?? AppResources.bundle.url(
            forResource: "fs-user-stories-core",
            withExtension: nil
        )
        guard let bundledURL else {
            throw RustCoreError.executableMissing
        }
        self.executableURL = bundledURL
    }

    func execute(_ command: [String: Any]) throws -> [String: Any] {
        let process = Process()
        process.executableURL = executableURL
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: JSONSerialization.data(withJSONObject: command))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        guard
            let response = try JSONSerialization.jsonObject(with: outputData) as? [String: Any],
            let succeeded = response["ok"] as? Bool
        else {
            let message = String(
                data: errors.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )
            throw RustCoreError.commandFailed(message ?? RustCoreError.invalidResponse.localizedDescription)
        }
        guard succeeded else {
            let error = response["error"] as? [String: Any]
            if error?["code"] as? String == "sync_conflicts",
               let details = error?["details"] as? [String: Any],
               let conflicts = details["conflicts"]
            {
                let data = try JSONSerialization.data(withJSONObject: conflicts)
                throw RustCoreError.syncConflicts(
                    try JSONDecoder().decode([CoreSyncConflict].self, from: data)
                )
            }
            throw RustCoreError.coreFailure(
                code: error?["code"] as? String ?? "core_error",
                message: error?["message"] as? String ?? L10n.string("Synchronization failed")
            )
        }
        return response["result"] as? [String: Any] ?? [:]
    }
}

struct CoreSyncConflict: Codable, Identifiable, Hashable, Sendable {
    var entityType: String
    var entityID: String

    var id: String { "\(entityType)-\(entityID)" }

    enum CodingKeys: String, CodingKey {
        case entityType
        case entityID = "entityId"
    }
}

struct GitSyncService: Sendable {
    private let core: RustCoreClient
    private let repositoriesRoot: URL

    var managedRepositoriesRootURL: URL { repositoriesRoot }

    init(
        core: RustCoreClient? = nil,
        repositoriesRoot: URL? = nil
    ) throws {
        self.core = try core ?? RustCoreClient()
        if let repositoriesRoot {
            self.repositoriesRoot = repositoriesRoot
        } else {
            let applicationSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.repositoriesRoot = applicationSupport
                .appending(path: "FS User Stories", directoryHint: .isDirectory)
                .appending(path: "Repositories", directoryHint: .isDirectory)
        }
        try FileManager.default.createDirectory(
            at: self.repositoriesRoot,
            withIntermediateDirectories: true
        )
    }

    func synchronizeStored(
        projectID: UUID,
        databaseURL: URL,
        attachmentsRootURL: URL,
        accessToken: String? = nil
    ) throws -> FSProject {
        var command: [String: Any] = [
            "command": "synchronize_stored_project",
            "database_path": databaseURL.path,
            "attachments_root": attachmentsRootURL.path,
            "project_id": projectID.uuidString
        ]
        if let accessToken { command["access_token"] = accessToken }
        let result = try core.execute(command)
        guard let project = result["project"] else { throw RustCoreError.invalidResponse }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            FSProject.self,
            from: JSONSerialization.data(withJSONObject: project)
        )
    }

    func initializeStored(
        projectID: UUID,
        databaseURL: URL,
        attachmentsRootURL: URL
    ) throws -> FSProject {
        try storedProjectResult([
            "command": "initialize_stored_project_repository",
            "database_path": databaseURL.path,
            "attachments_root": attachmentsRootURL.path,
            "project_id": projectID.uuidString,
            "repository_path": repositoryURL(for: projectID).path
        ])
    }

    func connectStored(
        projectID: UUID,
        databaseURL: URL,
        attachmentsRootURL: URL,
        remoteURL: String
    ) throws -> FSProject {
        try storedProjectResult([
            "command": "connect_stored_project_repository",
            "database_path": databaseURL.path,
            "attachments_root": attachmentsRootURL.path,
            "project_id": projectID.uuidString,
            "remote_url": remoteURL
        ])
    }

    func resolveStoredSynchronization(
        projectID: UUID,
        choices: [String: Bool],
        databaseURL: URL,
        attachmentsRootURL: URL,
        accessToken: String? = nil
    ) throws -> FSProject {
        let resolutions = choices.map { key, useShared -> [String: Any] in
            let parts = key.split(separator: "-", maxSplits: 1).map(String.init)
            return [
                "entityType": parts.first ?? "",
                "entityId": parts.count > 1 ? parts[1] : "",
                "choice": useShared ? "shared" : "mine"
            ]
        }
        var command: [String: Any] = [
            "command": "resolve_stored_project_synchronization",
            "database_path": databaseURL.path,
            "attachments_root": attachmentsRootURL.path,
            "project_id": projectID.uuidString,
            "resolutions": resolutions
        ]
        if let accessToken { command["access_token"] = accessToken }
        return try storedProjectResult(command)
    }

    func invitation(for project: FSProject) throws -> String {
        guard let link = project.gitRepository, let remoteURL = link.remoteURL else {
            throw RustCoreError.commandFailed(L10n.string("Connect a shared repository first."))
        }
        let result = try core.execute([
            "command": "create_invitation",
            "project_id": project.id.uuidString,
            "project_name": project.name,
            "remote_url": remoteURL,
            "default_branch": link.defaultBranch
        ])
        guard let invitation = result["invitation"] as? String else {
            throw RustCoreError.invalidResponse
        }
        return invitation
    }

    func invitationUsesGitHub(_ invitation: String) throws -> Bool {
        let result = try core.execute([
            "command": "read_invitation",
            "invitation": invitation.trimmingCharacters(in: .whitespacesAndNewlines)
        ])
        guard let remoteURL = result["remoteUrl"] as? String else {
            throw RustCoreError.invalidResponse
        }
        return try remoteUsesGitHub(remoteURL)
    }

    func joinStored(
        invitation: String,
        databaseURL: URL,
        attachmentsRootURL: URL,
        accessToken: String? = nil
    ) throws -> FSProject {
        let invitationResult = try core.execute([
            "command": "read_invitation",
            "invitation": invitation.trimmingCharacters(in: .whitespacesAndNewlines)
        ])
        guard let remoteURL = invitationResult["remoteUrl"] as? String else {
            throw RustCoreError.invalidResponse
        }
        return try joinStored(
            remoteURL: remoteURL,
            databaseURL: databaseURL,
            attachmentsRootURL: attachmentsRootURL,
            accessToken: accessToken
        )
    }

    func joinStored(
        remoteURL: String,
        databaseURL: URL,
        attachmentsRootURL: URL,
        accessToken: String? = nil
    ) throws -> FSProject {
        var command: [String: Any] = [
            "command": "join_stored_project",
            "database_path": databaseURL.path,
            "attachments_root": attachmentsRootURL.path,
            "repositories_root": repositoriesRoot.path,
            "remote_url": remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        if let accessToken { command["access_token"] = accessToken }
        return try storedProjectResult(command)
    }

    func remoteUsesGitHub(_ remoteURL: String) throws -> Bool {
        let result = try core.execute([
            "command": "remote_uses_git_hub",
            "remote_url": remoteURL
        ])
        guard let usesGitHub = result["usesGitHub"] as? Bool else {
            throw RustCoreError.invalidResponse
        }
        return usesGitHub
    }

    private func repositoryURL(for projectID: UUID) -> URL {
        repositoriesRoot.appending(path: projectID.uuidString, directoryHint: .isDirectory)
    }

    private func storedProjectResult(_ command: [String: Any]) throws -> FSProject {
        let result = try core.execute(command)
        guard let project = result["project"] else { throw RustCoreError.invalidResponse }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            FSProject.self,
            from: JSONSerialization.data(withJSONObject: project)
        )
    }

}
