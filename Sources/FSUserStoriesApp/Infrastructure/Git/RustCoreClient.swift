// SPDX-License-Identifier: MIT

import Foundation

enum RustCoreError: LocalizedError {
    case executableMissing
    case invalidResponse
    case commandFailed(String)
    case syncConflicts([CoreSyncConflict])

    var errorDescription: String? {
        switch self {
        case .executableMissing:
            "The bundled FS User Stories core is missing."
        case .invalidResponse:
            "The FS User Stories core returned an invalid response."
        case let .commandFailed(message):
            message
        case .syncConflicts:
            L10n.string("Some shared changes need your decision.")
        }
    }
}

struct RustCoreClient: Sendable {
    private let executableURL: URL

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
            throw RustCoreError.commandFailed(
                error?["message"] as? String ?? L10n.string("Synchronization failed")
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

    func initialize(_ project: FSProject, attachmentURLs: [UUID: URL]) throws -> GitRepositoryLink {
        let repositoryURL = repositoryURL(for: project.id)
        let result = try core.execute(
            command(
                named: "create_repository",
                project: project,
                repositoryURL: repositoryURL,
                attachmentURLs: attachmentURLs
            )
        )
        return GitRepositoryLink(
            localPath: repositoryURL.path,
            lastSyncedDigest: result["digest"] as? String
        )
    }

    func connect(_ project: FSProject, remoteURL: String) throws -> GitRepositoryLink {
        guard var link = project.gitRepository else {
            throw RustCoreError.commandFailed(L10n.string("The local repository is not ready."))
        }
        _ = try core.execute([
            "command": "connect_remote",
            "repository_path": link.localPath,
            "remote_url": remoteURL
        ])
        link.remoteURL = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return link
    }

    func synchronize(
        _ project: FSProject,
        attachmentURLs: [UUID: URL],
        accessToken: String? = nil
    ) throws -> GitSynchronizationResult {
        guard var link = project.gitRepository, link.remoteURL != nil else {
            throw RustCoreError.commandFailed(L10n.string("Connect a shared repository first."))
        }
        var syncCommand = try command(
                named: "synchronize",
                project: project,
                repositoryURL: URL(filePath: link.localPath, directoryHint: .isDirectory),
                attachmentURLs: attachmentURLs
            )
        if isGitHubURL(link.remoteURL), let accessToken {
            syncCommand["access_token"] = accessToken
        }
        let result = try core.execute(syncCommand)
        link.lastSyncedDigest = result["digest"] as? String
        link.lastSyncedAt = .now
        guard let snapshotObject = result["snapshot"] else {
            throw RustCoreError.invalidResponse
        }
        let data = try JSONSerialization.data(withJSONObject: snapshotObject)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return GitSynchronizationResult(
            link: link,
            snapshot: try decoder.decode(GitProjectSnapshot.self, from: data)
        )
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
        return isGitHubURL(remoteURL)
    }

    func join(invitation: String, accessToken: String? = nil) throws -> GitSynchronizationResult {
        let invitationResult = try core.execute([
            "command": "read_invitation",
            "invitation": invitation.trimmingCharacters(in: .whitespacesAndNewlines)
        ])
        guard
            let projectIDValue = invitationResult["projectId"] as? String,
            let projectID = UUID(uuidString: projectIDValue),
            let remoteURL = invitationResult["remoteUrl"] as? String
        else {
            throw RustCoreError.invalidResponse
        }
        let repositoryURL = repositoryURL(for: projectID)
        var cloneCommand: [String: Any] = [
            "command": "clone_shared",
            "repository_path": repositoryURL.path,
            "remote_url": remoteURL
        ]
        if isGitHubURL(remoteURL), let accessToken {
            cloneCommand["access_token"] = accessToken
        }
        let result = try core.execute(cloneCommand)
        let link = GitRepositoryLink(
            localPath: repositoryURL.path,
            remoteURL: remoteURL,
            defaultBranch: invitationResult["defaultBranch"] as? String ?? "fs-user-stories",
            lastSyncedAt: .now
        )
        let wrappedResult: [String: Any] = [
            "snapshot": result,
            "digest": NSNull()
        ]
        return try synchronizationResult(wrappedResult, link: link)
    }

    func resolveSynchronization(
        _ project: FSProject,
        choices: [String: Bool],
        attachmentURLs: [UUID: URL],
        accessToken: String? = nil
    ) throws -> GitSynchronizationResult {
        guard var link = project.gitRepository else {
            throw RustCoreError.commandFailed(L10n.string("The local repository is not ready."))
        }
        let resolutions = choices.map { key, useShared -> [String: Any] in
            let parts = key.split(separator: "-", maxSplits: 1).map(String.init)
            return [
                "entityType": parts.first ?? "",
                "entityId": parts.count > 1 ? parts[1] : "",
                "choice": useShared ? "shared" : "mine"
            ]
        }
        let attachmentSources = attachmentSourcePaths(
            project: project,
            attachmentURLs: attachmentURLs
        )
        var resolveCommand: [String: Any] = [
            "command": "resolve_synchronization",
            "repository_path": link.localPath,
            "resolutions": resolutions,
            "attachment_sources": attachmentSources
        ]
        if isGitHubURL(link.remoteURL), let accessToken {
            resolveCommand["access_token"] = accessToken
        }
        let result = try core.execute(resolveCommand)
        link.lastSyncedDigest = result["digest"] as? String
        link.lastSyncedAt = .now
        return try synchronizationResult(result, link: link)
    }

    private func repositoryURL(for projectID: UUID) -> URL {
        repositoriesRoot.appending(path: projectID.uuidString, directoryHint: .isDirectory)
    }

    private func command(
        named name: String,
        project: FSProject,
        repositoryURL: URL,
        attachmentURLs: [UUID: URL]
    ) throws -> [String: Any] {
        let archive = GitProjectArchive()
        let snapshot = archive.snapshot(for: project)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let snapshotObject = try JSONSerialization.jsonObject(with: encoder.encode(snapshot))
        let attachmentSources = attachmentSourcePaths(
            project: project,
            attachmentURLs: attachmentURLs
        )
        return [
            "command": name,
            "repository_path": repositoryURL.path,
            "snapshot": snapshotObject,
            "attachment_sources": attachmentSources
        ]
    }

    private func attachmentSourcePaths(
        project: FSProject,
        attachmentURLs: [UUID: URL]
    ) -> [String: String] {
        let archive = GitProjectArchive()
        var attachmentSources: [String: String] = [:]
        for story in project.stories {
            for attachment in story.attachments {
                guard let sourceURL = attachmentURLs[attachment.id] else { continue }
                attachmentSources[archive.archivePath(storyID: story.id, attachment: attachment)] = sourceURL.path
            }
        }
        return attachmentSources
    }

    private func synchronizationResult(
        _ result: [String: Any],
        link: GitRepositoryLink
    ) throws -> GitSynchronizationResult {
        guard let snapshotObject = result["snapshot"] else {
            throw RustCoreError.invalidResponse
        }
        let data = try JSONSerialization.data(withJSONObject: snapshotObject)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return GitSynchronizationResult(
            link: link,
            snapshot: try decoder.decode(GitProjectSnapshot.self, from: data)
        )
    }

    private func isGitHubURL(_ value: String?) -> Bool {
        guard let value = value?.lowercased() else { return false }
        return value.hasPrefix("https://github.com/")
            || value.hasPrefix("ssh://git@github.com/")
            || value.hasPrefix("git@github.com:")
    }
}

struct GitSynchronizationResult: Sendable {
    var link: GitRepositoryLink
    var snapshot: GitProjectSnapshot
}
