// SPDX-License-Identifier: MIT

import Foundation
import Observation

enum WorkspaceAction: Equatable {
    case createStory(projectID: UUID)
}

enum ProjectSyncState: Equatable {
    case idle
    case working
    case succeeded(Date)
    case failed(String)
}

@MainActor
@Observable
final class AppStore {
    private(set) var projects: [FSProject]
    private(set) var persistenceError: String?
    private(set) var mcpServerState: MCPServerState = .stopped
    private(set) var projectSyncState: ProjectSyncState = .idle
    private(set) var pendingSyncConflicts: [CoreSyncConflict] = []
    var selectedProjectID: UUID?
    var selectedStoryID: UUID?
    var pendingWorkspaceAction: WorkspaceAction?
    private let persistenceStore: PersistenceStore?
    private let attachmentStorage: AttachmentStorage?
    private let gitSyncService: GitSyncService?
    private let gitHubService: GitHubService
    @ObservationIgnored private var sessionGitHubAccessToken: String?
    @ObservationIgnored private var localMCPServer: LocalMCPServer?

    init(
        projects: [FSProject] = [],
        persistenceStore: PersistenceStore? = nil,
        attachmentStorage: AttachmentStorage? = nil,
        gitSyncService: GitSyncService? = nil,
        gitHubService: GitHubService = GitHubService()
    ) {
        self.projects = projects
        self.persistenceStore = persistenceStore
        self.attachmentStorage = attachmentStorage
        self.gitSyncService = gitSyncService
        self.gitHubService = gitHubService
        self.selectedProjectID = projects.first?.id
        self.selectedStoryID = projects.first?.stories.first?.id
    }

    static func persistent() throws -> AppStore {
        let persistenceStore = try PersistenceStore()
        let store = AppStore(
            projects: try persistenceStore.loadProjects(),
            persistenceStore: persistenceStore,
            attachmentStorage: try AttachmentStorage(),
            gitSyncService: try GitSyncService()
        )
        store.startMCPServer()
        store.ensureManagedRepositories()
        return store
    }

    var mcpServerURL: URL {
        localMCPServer?.endpointURL ?? URL(
            string: "http://127.0.0.1:\(LocalMCPServer.defaultPort)/mcp"
        )!
    }

    var gitHubRepositoryCreationIsConfigured: Bool {
        gitHubService.isConfigured
    }

    var gitHubIsAuthorized: Bool {
        githubAccessToken() != nil
    }

    private func githubAccessToken() -> String? {
        sessionGitHubAccessToken ?? (try? gitHubService.storedToken())
    }

    private func startMCPServer() {
        let server = LocalMCPServer(
            handler: { [weak self] request in
                self?.handleMCPRequest(request)
            },
            resourceHandler: { [weak self] attachmentID in
                self?.mcpAttachmentResource(attachmentID)
            },
            stateChanged: { [weak self] state in
                self?.mcpServerState = state
            }
        )
        localMCPServer = server
        mcpServerState = .starting
        do {
            try server.start()
        } catch {
            mcpServerState = .failed(error.localizedDescription)
        }
    }

    var selectedProject: FSProject? {
        guard let selectedProjectID else { return nil }
        return projects.first { $0.id == selectedProjectID }
    }

    var selectedStory: UserStory? {
        guard
            let project = selectedProject,
            let selectedStoryID
        else {
            return nil
        }

        return project.stories.first { $0.id == selectedStoryID }
    }

    @discardableResult
    func createProject(name: String, prefix: String) -> Result<FSProject, WorkspaceError> {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedName.isEmpty else { return .failure(.nameRequired) }
        guard !normalizedPrefix.isEmpty else { return .failure(.prefixRequired) }
        let project = FSProject(
            name: normalizedName,
            prefix: normalizedPrefix
        )
        projects.append(project)
        selectedProjectID = project.id
        selectedStoryID = nil
        if let gitSyncService {
            do {
                projects[projects.count - 1].gitRepository = try gitSyncService.initialize(
                    project,
                    attachmentURLs: [:]
                )
            } catch {
                projects.removeLast()
                selectedProjectID = projects.first?.id
                return .failure(.persistenceFailure(error.localizedDescription))
            }
        }
        guard persist() else {
            return .failure(.persistenceFailure(persistenceError ?? "The project could not be saved"))
        }
        return .success(projects[projects.count - 1])
    }

    func connectSharedRepository(remoteURL: String, projectID: UUID) async -> Result<Void, WorkspaceError> {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard let gitSyncService else {
            return .failure(.persistenceFailure("The synchronization core is unavailable"))
        }
        let project = projects[projectIndex]
        let attachmentURLs = Dictionary(
            uniqueKeysWithValues: project.stories.flatMap(\.attachments).compactMap { attachment in
                attachmentURL(for: attachment).map { (attachment.id, $0) }
            }
        )
        projectSyncState = .working
        do {
            let link = try await Task.detached {
                var preparedProject = project
                if preparedProject.gitRepository == nil {
                    preparedProject.gitRepository = try gitSyncService.initialize(
                        project,
                        attachmentURLs: attachmentURLs
                    )
                }
                return try gitSyncService.connect(preparedProject, remoteURL: remoteURL)
            }.value
            guard let currentIndex = projects.firstIndex(where: { $0.id == projectID }) else {
                return .failure(.projectNotFound)
            }
            projects[currentIndex].gitRepository = link
            guard persist() else {
                throw WorkspaceError.persistenceFailure(
                    persistenceError ?? "The repository connection could not be saved"
                )
            }
            projectSyncState = .idle
            return .success(())
        } catch {
            projectSyncState = .failed(error.localizedDescription)
            return .failure(.persistenceFailure(error.localizedDescription))
        }
    }

    func prepareManagedRepository(_ projectID: UUID) async -> Result<Void, WorkspaceError> {
        guard let project = projects.first(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard let gitSyncService else {
            return .failure(.persistenceFailure("The synchronization core is unavailable"))
        }
        let attachmentURLs = Dictionary(
            uniqueKeysWithValues: project.stories.flatMap(\.attachments).compactMap { attachment in
                attachmentURL(for: attachment).map { (attachment.id, $0) }
            }
        )
        projectSyncState = .working
        do {
            let link = try await Task.detached {
                try gitSyncService.initialize(project, attachmentURLs: attachmentURLs)
            }.value
            guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
                return .failure(.projectNotFound)
            }
            projects[projectIndex].gitRepository = link
            guard persist() else {
                throw WorkspaceError.persistenceFailure(
                    persistenceError ?? "The managed repository could not be saved"
                )
            }
            projectSyncState = .idle
            return .success(())
        } catch {
            projectSyncState = .failed(error.localizedDescription)
            return .failure(.persistenceFailure(error.localizedDescription))
        }
    }

    func resolveProjectSynchronization(
        _ projectID: UUID,
        choices: [String: Bool]
    ) async -> Result<Void, WorkspaceError> {
        guard let project = projects.first(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard choices.count == pendingSyncConflicts.count else {
            return .failure(.persistenceFailure(L10n.string("Choose a version for every conflict.")))
        }
        guard let gitSyncService else {
            return .failure(.persistenceFailure("The synchronization core is unavailable"))
        }
        let attachmentURLs = Dictionary(
            uniqueKeysWithValues: project.stories.flatMap(\.attachments).compactMap { attachment in
                attachmentURL(for: attachment).map { (attachment.id, $0) }
            }
        )
        let accessToken = githubAccessToken()
        projectSyncState = .working
        do {
            let synchronization = try await Task.detached {
                try gitSyncService.resolveSynchronization(
                    project,
                    choices: choices,
                    attachmentURLs: attachmentURLs,
                    accessToken: accessToken
                )
            }.value
            guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
                return .failure(.projectNotFound)
            }
            projects[projectIndex] = try projectFromSynchronizedSnapshot(
                synchronization.snapshot,
                link: synchronization.link
            )
            guard persist() else {
                throw WorkspaceError.persistenceFailure(
                    persistenceError ?? "The synchronization state could not be saved"
                )
            }
            pendingSyncConflicts = []
            projectSyncState = .succeeded(synchronization.link.lastSyncedAt ?? .now)
            return .success(())
        } catch {
            projectSyncState = .failed(error.localizedDescription)
            return .failure(.persistenceFailure(error.localizedDescription))
        }
    }

    func synchronizeProject(_ projectID: UUID) async -> Result<Void, WorkspaceError> {
        guard let project = projects.first(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard let gitSyncService else {
            return .failure(.persistenceFailure("The synchronization core is unavailable"))
        }
        let attachmentURLs = Dictionary(
            uniqueKeysWithValues: project.stories.flatMap(\.attachments).compactMap { attachment in
                attachmentURL(for: attachment).map { (attachment.id, $0) }
            }
        )
        let accessToken = githubAccessToken()
        projectSyncState = .working
        do {
            let synchronization = try await Task.detached {
                try gitSyncService.synchronize(
                    project,
                    attachmentURLs: attachmentURLs,
                    accessToken: accessToken
                )
            }.value
            guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
                return .failure(.projectNotFound)
            }
            projects[projectIndex] = try projectFromSynchronizedSnapshot(
                synchronization.snapshot,
                link: synchronization.link
            )
            guard persist() else {
                throw WorkspaceError.persistenceFailure(
                    persistenceError ?? "The synchronization state could not be saved"
                )
            }
            projectSyncState = .succeeded(synchronization.link.lastSyncedAt ?? .now)
            return .success(())
        } catch let RustCoreError.syncConflicts(conflicts) {
            pendingSyncConflicts = conflicts
            projectSyncState = .failed(L10n.string("Some shared changes need your decision."))
            return .failure(.persistenceFailure(L10n.string("Some shared changes need your decision.")))
        } catch {
            projectSyncState = .failed(error.localizedDescription)
            return .failure(.persistenceFailure(error.localizedDescription))
        }
    }

    func projectInvitation(_ projectID: UUID) async -> Result<String, WorkspaceError> {
        guard let project = projects.first(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard let gitSyncService else {
            return .failure(.persistenceFailure("The synchronization core is unavailable"))
        }
        do {
            let invitation = try await Task.detached {
                try gitSyncService.invitation(for: project)
            }.value
            return .success(invitation)
        } catch {
            return .failure(.persistenceFailure(error.localizedDescription))
        }
    }

    func beginGitHubRepositoryCreation() async -> Result<GitHubDeviceAuthorization, WorkspaceError> {
        do {
            return .success(try await gitHubService.beginAuthorization())
        } catch {
            return .failure(.persistenceFailure(error.localizedDescription))
        }
    }

    func finishGitHubAuthorization(
        _ authorization: GitHubDeviceAuthorization
    ) async -> Result<Void, WorkspaceError> {
        do {
            sessionGitHubAccessToken = try await gitHubService.finishAuthorization(authorization)
            return .success(())
        } catch {
            return .failure(.persistenceFailure(error.localizedDescription))
        }
    }

    func sharedInvitationUsesGitHub(_ invitation: String) -> Result<Bool, WorkspaceError> {
        guard let gitSyncService else {
            return .failure(.persistenceFailure("The synchronization core is unavailable"))
        }
        do {
            return .success(try gitSyncService.invitationUsesGitHub(invitation))
        } catch {
            return .failure(.persistenceFailure(error.localizedDescription))
        }
    }

    func inviteGitHubCollaborator(
        username: String,
        projectID: UUID
    ) async -> Result<Void, WorkspaceError> {
        guard let project = projects.first(where: { $0.id == projectID }),
              let remoteURL = project.gitRepository?.remoteURL else {
            return .failure(.projectNotFound)
        }
        guard let token = githubAccessToken() else {
            return .failure(
                .persistenceFailure(L10n.string("Connect your GitHub account before inviting a collaborator."))
            )
        }
        do {
            try await gitHubService.inviteCollaborator(
                username: username,
                repositoryURL: remoteURL,
                token: token
            )
            return .success(())
        } catch {
            return .failure(.persistenceFailure(error.localizedDescription))
        }
    }

    func finishGitHubRepositoryCreation(
        authorization: GitHubDeviceAuthorization,
        projectID: UUID
    ) async -> Result<GitHubRepository, WorkspaceError> {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard let gitSyncService else {
            return .failure(.persistenceFailure("The synchronization core is unavailable"))
        }
        projectSyncState = .working
        do {
            let project = projects[projectIndex]
            let attachmentURLs = Dictionary(
                uniqueKeysWithValues: project.stories.flatMap(\.attachments).compactMap { attachment in
                    attachmentURL(for: attachment).map { (attachment.id, $0) }
                }
            )
            var connectedProject = project
            if connectedProject.gitRepository == nil {
                connectedProject.gitRepository = try await Task.detached {
                    try gitSyncService.initialize(project, attachmentURLs: attachmentURLs)
                }.value
            }
            let token = try await gitHubService.finishAuthorization(authorization)
            sessionGitHubAccessToken = token
            let repository = try await gitHubService.createPrivateRepository(
                name: project.name,
                token: token
            )
            connectedProject.gitRepository = try gitSyncService.connect(
                connectedProject,
                remoteURL: repository.cloneURL
            )
            let synchronization = try await Task.detached {
                try gitSyncService.synchronize(
                    connectedProject,
                    attachmentURLs: attachmentURLs,
                    accessToken: token
                )
            }.value
            guard let currentIndex = projects.firstIndex(where: { $0.id == projectID }) else {
                return .failure(.projectNotFound)
            }
            projects[currentIndex] = try projectFromSynchronizedSnapshot(
                synchronization.snapshot,
                link: synchronization.link
            )
            guard persist() else {
                throw WorkspaceError.persistenceFailure(
                    persistenceError ?? "The GitHub repository could not be saved"
                )
            }
            projectSyncState = .succeeded(.now)
            return .success(repository)
        } catch {
            projectSyncState = .failed(error.localizedDescription)
            return .failure(.persistenceFailure(error.localizedDescription))
        }
    }

    func connectSharedRepositoryFromMCP(
        remoteURL: String,
        projectID: UUID
    ) -> Result<FSProject, WorkspaceError> {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard let gitSyncService else {
            return .failure(.persistenceFailure("The synchronization core is unavailable"))
        }
        do {
            projects[projectIndex].gitRepository = try gitSyncService.connect(
                projects[projectIndex],
                remoteURL: remoteURL
            )
            guard persist() else {
                throw WorkspaceError.persistenceFailure(
                    persistenceError ?? "The repository connection could not be saved"
                )
            }
            return .success(projects[projectIndex])
        } catch {
            return .failure(.persistenceFailure(error.localizedDescription))
        }
    }

    func synchronizeProjectFromMCP(_ projectID: UUID) -> Result<FSProject, WorkspaceError> {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard let gitSyncService else {
            return .failure(.persistenceFailure("The synchronization core is unavailable"))
        }
        let project = projects[projectIndex]
        let attachmentURLs = Dictionary(
            uniqueKeysWithValues: project.stories.flatMap(\.attachments).compactMap { attachment in
                attachmentURL(for: attachment).map { (attachment.id, $0) }
            }
        )
        do {
            let synchronization = try gitSyncService.synchronize(
                project,
                attachmentURLs: attachmentURLs,
                accessToken: githubAccessToken()
            )
            projects[projectIndex] = try projectFromSynchronizedSnapshot(
                synchronization.snapshot,
                link: synchronization.link
            )
            guard persist() else {
                throw WorkspaceError.persistenceFailure(
                    persistenceError ?? "The synchronization state could not be saved"
                )
            }
            return .success(projects[projectIndex])
        } catch let RustCoreError.syncConflicts(conflicts) {
            pendingSyncConflicts = conflicts
            return .failure(.persistenceFailure(L10n.string("Some shared changes need your decision.")))
        } catch {
            return .failure(.persistenceFailure(error.localizedDescription))
        }
    }

    func projectInvitationFromMCP(_ projectID: UUID) -> Result<String, WorkspaceError> {
        guard let project = projects.first(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard let gitSyncService else {
            return .failure(.persistenceFailure("The synchronization core is unavailable"))
        }
        do {
            return .success(try gitSyncService.invitation(for: project))
        } catch {
            return .failure(.persistenceFailure(error.localizedDescription))
        }
    }

    func joinSharedProject(invitation: String) async -> Result<FSProject, WorkspaceError> {
        guard let gitSyncService else {
            return .failure(.persistenceFailure("The synchronization core is unavailable"))
        }
        let accessToken = githubAccessToken()
        projectSyncState = .working
        do {
            let synchronization = try await Task.detached {
                try gitSyncService.join(
                    invitation: invitation,
                    accessToken: accessToken
                )
            }.value
            guard !projects.contains(where: { $0.id == synchronization.snapshot.projectID }) else {
                throw WorkspaceError.persistenceFailure(L10n.string("This shared project is already on this Mac."))
            }
            let project = try projectFromSynchronizedSnapshot(
                synchronization.snapshot,
                link: synchronization.link
            )
            projects.append(project)
            selectedProjectID = project.id
            selectedStoryID = project.stories.first?.id
            guard persist() else {
                throw WorkspaceError.persistenceFailure(
                    persistenceError ?? "The shared project could not be saved"
                )
            }
            projectSyncState = .succeeded(.now)
            return .success(project)
        } catch {
            projectSyncState = .failed(error.localizedDescription)
            return .failure(.persistenceFailure(error.localizedDescription))
        }
    }

    private func ensureManagedRepositories() {
        guard let gitSyncService else { return }
        var changed = false
        for index in projects.indices where projects[index].gitRepository == nil {
            do {
                let project = projects[index]
                let attachmentURLs = Dictionary(
                    uniqueKeysWithValues: project.stories.flatMap(\.attachments).compactMap { attachment in
                        attachmentURL(for: attachment).map { (attachment.id, $0) }
                    }
                )
                projects[index].gitRepository = try gitSyncService.initialize(
                    project,
                    attachmentURLs: attachmentURLs
                )
                changed = true
            } catch {
                projectSyncState = .failed(error.localizedDescription)
            }
        }
        if changed { _ = persist() }
    }

    private func projectFromSynchronizedSnapshot(
        _ snapshot: GitProjectSnapshot,
        link: GitRepositoryLink
    ) throws -> FSProject {
        let actors = snapshot.actors.map {
            ProjectActor(id: $0.id, name: $0.name, role: $0.role)
        }
        var stories: [UserStory] = []
        let archiveRoot = URL(filePath: link.localPath, directoryHint: .isDirectory)
            .appending(path: GitProjectArchive.directoryName, directoryHint: .isDirectory)
        for story in snapshot.stories {
            var attachments: [StoryAttachment] = []
            for metadata in story.attachments {
                let sourceURL = archiveRoot.appending(path: metadata.archiveRelativePath)
                if let attachmentStorage {
                    attachments.append(
                        try attachmentStorage.restoreFile(
                            from: sourceURL,
                            metadata: metadata,
                            projectID: snapshot.projectID,
                            storyID: story.id
                        )
                    )
                }
            }
            stories.append(
                UserStory(
                    id: story.id,
                    number: story.number,
                    title: story.title,
                    actorID: story.actorID,
                    want: story.want,
                    outcome: story.outcome,
                    notes: story.notes,
                    acceptanceCriteria: story.acceptanceCriteria.map {
                        AcceptanceCriterion(id: $0.id, text: $0.text, isMet: $0.isMet)
                    },
                    attachments: attachments,
                    status: StoryStatus(rawValue: story.status) ?? .draft,
                    createdAt: story.createdAt
                )
            )
        }
        return FSProject(
            id: snapshot.projectID,
            name: snapshot.name,
            prefix: snapshot.prefix,
            actors: actors,
            stories: stories,
            gitRepository: link
        )
    }

    func selectStory(_ storyID: UUID, in projectID: UUID) {
        selectedProjectID = projectID
        selectedStoryID = storyID
    }

    func requestStoryCreation(in projectID: UUID) {
        selectedProjectID = projectID
        selectedStoryID = nil
        pendingWorkspaceAction = .createStory(projectID: projectID)
    }

    @discardableResult
    func addActor(name: String, role: String, to projectID: UUID) -> Result<ProjectActor, WorkspaceError> {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return .failure(.nameRequired) }
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }

        let actor = ProjectActor(
            name: normalizedName,
            role: role.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        projects[projectIndex].actors.append(actor)
        guard persist() else {
            return .failure(.persistenceFailure(persistenceError ?? "The actor could not be saved"))
        }
        return .success(actor)
    }

    @discardableResult
    func updateActor(
        _ actorID: UUID,
        name: String,
        role: String,
        projectID: UUID
    ) -> Result<ProjectActor, WorkspaceError> {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return .failure(.nameRequired) }
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard let actorIndex = projects[projectIndex].actors.firstIndex(where: { $0.id == actorID }) else {
            return .failure(.actorNotFound)
        }

        projects[projectIndex].actors[actorIndex].name = normalizedName
        projects[projectIndex].actors[actorIndex].role = role
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard persist() else {
            return .failure(.persistenceFailure(persistenceError ?? "The actor could not be saved"))
        }
        return .success(projects[projectIndex].actors[actorIndex])
    }

    @discardableResult
    func deleteActor(_ actorID: UUID, projectID: UUID) -> Result<Void, WorkspaceError> {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard let actorIndex = projects[projectIndex].actors.firstIndex(where: { $0.id == actorID }) else {
            return .failure(.actorNotFound)
        }
        guard !projects[projectIndex].stories.contains(where: { $0.actorID == actorID }) else {
            return .failure(.actorInUse)
        }

        projects[projectIndex].actors.remove(at: actorIndex)
        guard persist() else {
            return .failure(.persistenceFailure(persistenceError ?? "The actor could not be deleted"))
        }
        return .success(())
    }

    @discardableResult
    func addStory(
        title: String,
        actorID: UUID,
        want: String,
        outcome: String,
        acceptanceCriteria: [AcceptanceCriterion],
        to projectID: UUID
    ) -> Result<UserStory, WorkspaceError> {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedWant = want.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOutcome = outcome.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCriteria = acceptanceCriteria.compactMap { criterion -> AcceptanceCriterion? in
            let text = criterion.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : AcceptanceCriterion(id: criterion.id, text: text, isMet: criterion.isMet)
        }
        guard !normalizedTitle.isEmpty else { return .failure(.titleRequired) }
        guard !normalizedWant.isEmpty else { return .failure(.wantRequired) }
        guard !normalizedOutcome.isEmpty else { return .failure(.outcomeRequired) }
        guard !normalizedCriteria.isEmpty else { return .failure(.acceptanceCriterionRequired) }
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard projects[projectIndex].actors.contains(where: { $0.id == actorID }) else {
            return .failure(.actorNotFound)
        }

        let nextNumber = (projects[projectIndex].stories.map(\.number).max() ?? 0) + 1
        let story = UserStory(
            number: nextNumber,
            title: normalizedTitle,
            actorID: actorID,
            want: normalizedWant,
            outcome: normalizedOutcome,
            acceptanceCriteria: normalizedCriteria
        )

        projects[projectIndex].stories.append(story)
        selectedStoryID = story.id
        guard persist() else {
            return .failure(.persistenceFailure(persistenceError ?? "The story could not be saved"))
        }
        return .success(story)
    }

    @discardableResult
    func updateStory(
        _ storyID: UUID,
        title: String,
        actorID: UUID,
        want: String,
        outcome: String,
        acceptanceCriteria: [AcceptanceCriterion],
        projectID: UUID
    ) -> Result<UserStory, WorkspaceError> {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedWant = want.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOutcome = outcome.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCriteria = acceptanceCriteria.compactMap { criterion -> AcceptanceCriterion? in
            let text = criterion.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : AcceptanceCriterion(id: criterion.id, text: text, isMet: criterion.isMet)
        }
        guard !normalizedTitle.isEmpty else { return .failure(.titleRequired) }
        guard !normalizedWant.isEmpty else { return .failure(.wantRequired) }
        guard !normalizedOutcome.isEmpty else { return .failure(.outcomeRequired) }
        guard !normalizedCriteria.isEmpty else { return .failure(.acceptanceCriterionRequired) }
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard projects[projectIndex].actors.contains(where: { $0.id == actorID }) else {
            return .failure(.actorNotFound)
        }
        guard let storyIndex = projects[projectIndex].stories.firstIndex(where: { $0.id == storyID }) else {
            return .failure(.storyNotFound)
        }
        guard projects[projectIndex].stories[storyIndex].status != .done else {
            return .failure(.completedStoryReadOnly)
        }

        projects[projectIndex].stories[storyIndex].title = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
        projects[projectIndex].stories[storyIndex].actorID = actorID
        projects[projectIndex].stories[storyIndex].want = want
            .trimmingCharacters(in: .whitespacesAndNewlines)
        projects[projectIndex].stories[storyIndex].outcome = outcome
            .trimmingCharacters(in: .whitespacesAndNewlines)
        projects[projectIndex].stories[storyIndex].acceptanceCriteria = normalizedCriteria
        guard persist() else {
            return .failure(.persistenceFailure(persistenceError ?? "The story could not be saved"))
        }
        return .success(projects[projectIndex].stories[storyIndex])
    }

    @discardableResult
    func toggleAcceptanceCriterion(
        _ criterionID: UUID,
        in storyID: UUID,
        projectID: UUID
    ) -> Result<UserStory, WorkspaceError> {
        guard let project = projects.first(where: { $0.id == projectID }),
              let story = project.stories.first(where: { $0.id == storyID }),
              let criterion = story.acceptanceCriteria.first(where: { $0.id == criterionID }) else {
            return .failure(.criterionNotFound)
        }
        return setAcceptanceCriterion(
            criterionID,
            isMet: !criterion.isMet,
            in: storyID,
            projectID: projectID
        )
    }

    @discardableResult
    func setAcceptanceCriterion(
        _ criterionID: UUID,
        isMet: Bool,
        in storyID: UUID,
        projectID: UUID
    ) -> Result<UserStory, WorkspaceError> {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard let storyIndex = projects[projectIndex].stories.firstIndex(where: { $0.id == storyID }) else {
            return .failure(.storyNotFound)
        }
        guard projects[projectIndex].stories[storyIndex].status != .done else {
            return .failure(.completedStoryReadOnly)
        }
        guard let criterionIndex = projects[projectIndex].stories[storyIndex].acceptanceCriteria
            .firstIndex(where: { $0.id == criterionID }) else {
            return .failure(.criterionNotFound)
        }
        projects[projectIndex].stories[storyIndex].acceptanceCriteria[criterionIndex].isMet = isMet
        guard persist() else {
            return .failure(.persistenceFailure(persistenceError ?? "The criterion could not be saved"))
        }
        return .success(projects[projectIndex].stories[storyIndex])
    }

    @discardableResult
    func addAcceptanceCriterion(
        text: String,
        to storyID: UUID,
        projectID: UUID
    ) -> Result<UserStory, WorkspaceError> {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return .failure(.acceptanceCriterionRequired) }
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard let storyIndex = projects[projectIndex].stories.firstIndex(where: { $0.id == storyID }) else {
            return .failure(.storyNotFound)
        }
        guard projects[projectIndex].stories[storyIndex].status != .done else {
            return .failure(.completedStoryReadOnly)
        }

        projects[projectIndex].stories[storyIndex].acceptanceCriteria.append(
            AcceptanceCriterion(text: trimmedText)
        )
        guard persist() else {
            return .failure(.persistenceFailure(persistenceError ?? "The criterion could not be saved"))
        }
        return .success(projects[projectIndex].stories[storyIndex])
    }

    @discardableResult
    func setStoryStatus(
        _ status: StoryStatus,
        for storyID: UUID,
        projectID: UUID
    ) -> Result<UserStory, WorkspaceError> {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard let storyIndex = projects[projectIndex].stories.firstIndex(where: { $0.id == storyID }) else {
            return .failure(.storyNotFound)
        }
        let story = projects[projectIndex].stories[storyIndex]
        if status == .done,
           story.acceptanceCriteria.isEmpty || story.metCriteriaCount != story.acceptanceCriteria.count {
            return .failure(.incompleteAcceptanceCriteria)
        }

        projects[projectIndex].stories[storyIndex].status = status
        guard persist() else {
            return .failure(.persistenceFailure(persistenceError ?? "The story status could not be saved"))
        }
        return .success(projects[projectIndex].stories[storyIndex])
    }

    @discardableResult
    func duplicateStory(_ storyID: UUID, projectID: UUID) -> Result<UserStory, WorkspaceError> {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard let source = projects[projectIndex].stories.first(where: { $0.id == storyID }) else {
            return .failure(.storyNotFound)
        }

        let nextNumber = (projects[projectIndex].stories.map(\.number).max() ?? 0) + 1
        let duplicatedStory = UserStory(
            number: nextNumber,
            title: String(format: L10n.string("Copy of %@"), source.title),
            actorID: source.actorID,
            want: source.want,
            outcome: source.outcome,
            notes: source.notes,
            acceptanceCriteria: source.acceptanceCriteria.map {
                AcceptanceCriterion(text: $0.text)
            },
            status: .draft
        )

        projects[projectIndex].stories.append(duplicatedStory)
        selectedStoryID = duplicatedStory.id
        guard persist() else {
            return .failure(.persistenceFailure(persistenceError ?? "The story could not be duplicated"))
        }
        return .success(duplicatedStory)
    }

    @discardableResult
    func updateStoryNotes(
        _ notes: String,
        for storyID: UUID,
        projectID: UUID
    ) -> Result<UserStory, WorkspaceError> {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard let storyIndex = projects[projectIndex].stories.firstIndex(where: { $0.id == storyID }) else {
            return .failure(.storyNotFound)
        }
        guard projects[projectIndex].stories[storyIndex].status != .done else {
            return .failure(.completedStoryReadOnly)
        }

        projects[projectIndex].stories[storyIndex].notes = notes
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard persist() else {
            return .failure(.persistenceFailure(persistenceError ?? "The notes could not be saved"))
        }
        return .success(projects[projectIndex].stories[storyIndex])
    }

    @discardableResult
    func deleteStory(_ storyID: UUID, projectID: UUID) -> Result<Void, WorkspaceError> {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard let storyIndex = projects[projectIndex].stories.firstIndex(where: { $0.id == storyID }) else {
            return .failure(.storyNotFound)
        }

        projects[projectIndex].stories.remove(at: storyIndex)
        if selectedStoryID == storyID {
            let remainingStories = projects[projectIndex].stories
            selectedStoryID = remainingStories.isEmpty
                ? nil
                : remainingStories[min(storyIndex, remainingStories.count - 1)].id
        }
        if persist() {
            try? attachmentStorage?.removeStoryDirectory(projectID: projectID, storyID: storyID)
            return .success(())
        }
        return .failure(.persistenceFailure(persistenceError ?? "The story could not be deleted"))
    }

    func attachmentURL(for attachment: StoryAttachment) -> URL? {
        attachmentStorage?.url(for: attachment)
    }

    func addAttachments(
        from urls: [URL],
        to storyID: UUID,
        projectID: UUID
    ) -> String? {
        switch importAttachments(from: urls, to: storyID, projectID: projectID) {
        case .success:
            return nil
        case let .failure(error):
            return error.localizedDescription
        }
    }

    @discardableResult
    func importAttachments(
        from urls: [URL],
        to storyID: UUID,
        projectID: UUID
    ) -> Result<UserStory, WorkspaceError> {
        guard !urls.isEmpty else { return .failure(.attachmentsRequired) }
        guard let attachmentStorage else {
            return .failure(.attachmentFailure("Attachment storage is unavailable"))
        }
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard let storyIndex = projects[projectIndex].stories.firstIndex(where: { $0.id == storyID }) else {
            return .failure(.storyNotFound)
        }
        guard projects[projectIndex].stories[storyIndex].status != .done else {
            return .failure(.completedStoryReadOnly)
        }

        let existingAttachments = projects[projectIndex].stories[storyIndex].attachments
        guard existingAttachments.count + urls.count <= AttachmentStorage.maximumFilesPerStory else {
            return .failure(.attachmentFailure(L10n.string("A story can have up to 10 attachments.")))
        }

        do {
            let files = try urls.map(attachmentStorage.preflight)
            let existingSize = existingAttachments.reduce(Int64(0)) { $0 + $1.byteSize }
            let addedSize = files.reduce(Int64(0)) { $0 + $1.byteSize }
            guard existingSize + addedSize <= AttachmentStorage.maximumStorySize else {
                return .failure(.attachmentFailure(L10n.string("Attachments for a story cannot exceed 50 MB.")))
            }

            var importedAttachments: [StoryAttachment] = []
            do {
                for url in urls {
                    importedAttachments.append(
                        try attachmentStorage.importFile(
                            from: url,
                            projectID: projectID,
                            storyID: storyID
                        )
                    )
                }
            } catch {
                for attachment in importedAttachments {
                    try? attachmentStorage.remove(attachment)
                }
                throw error
            }

            projects[projectIndex].stories[storyIndex].attachments.append(contentsOf: importedAttachments)
            guard persist() else {
                projects[projectIndex].stories[storyIndex].attachments.removeAll {
                    importedAttachments.contains($0)
                }
                for attachment in importedAttachments {
                    try? attachmentStorage.remove(attachment)
                }
                return .failure(.attachmentFailure(L10n.string("The attachments could not be saved.")))
            }
            return .success(projects[projectIndex].stories[storyIndex])
        } catch let error as AttachmentStorageError {
            switch error {
            case let .fileTooLarge(filename):
                return .failure(.attachmentFailure(
                    String(format: L10n.string("%@ is larger than 10 MB."), filename)
                ))
            case let .notAFile(filename):
                return .failure(.attachmentFailure(
                    String(format: L10n.string("%@ is not a supported file."), filename)
                ))
            }
        } catch {
            return .failure(.attachmentFailure(String(
                format: L10n.string("The attachment could not be added: %@"),
                error.localizedDescription
            )))
        }
    }

    func deleteAttachment(
        _ attachmentID: UUID,
        from storyID: UUID,
        projectID: UUID
    ) -> String? {
        switch removeAttachment(attachmentID, from: storyID, projectID: projectID) {
        case .success:
            return nil
        case let .failure(error):
            return error.localizedDescription
        }
    }

    @discardableResult
    func removeAttachment(
        _ attachmentID: UUID,
        from storyID: UUID,
        projectID: UUID
    ) -> Result<Void, WorkspaceError> {
        guard let attachmentStorage else {
            return .failure(.attachmentFailure("Attachment storage is unavailable"))
        }
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard let storyIndex = projects[projectIndex].stories.firstIndex(where: { $0.id == storyID }) else {
            return .failure(.storyNotFound)
        }
        guard projects[projectIndex].stories[storyIndex].status != .done else {
            return .failure(.completedStoryReadOnly)
        }
        guard let attachmentIndex = projects[projectIndex].stories[storyIndex].attachments
            .firstIndex(where: { $0.id == attachmentID }) else {
            return .failure(.attachmentNotFound)
        }

        let attachment = projects[projectIndex].stories[storyIndex].attachments[attachmentIndex]
        do {
            try attachmentStorage.remove(attachment)
            projects[projectIndex].stories[storyIndex].attachments.remove(at: attachmentIndex)
            persist()
            return .success(())
        } catch {
            return .failure(.attachmentFailure(String(
                format: L10n.string("The attachment could not be deleted: %@"),
                error.localizedDescription
            )))
        }
    }

    @discardableResult
    func deleteAcceptanceCriterion(
        _ criterionID: UUID,
        from storyID: UUID,
        projectID: UUID
    ) -> Result<UserStory, WorkspaceError> {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard let storyIndex = projects[projectIndex].stories.firstIndex(where: { $0.id == storyID }) else {
            return .failure(.storyNotFound)
        }
        guard projects[projectIndex].stories[storyIndex].status != .done else {
            return .failure(.completedStoryReadOnly)
        }
        guard projects[projectIndex].stories[storyIndex].acceptanceCriteria
            .contains(where: { $0.id == criterionID }) else {
            return .failure(.criterionNotFound)
        }

        projects[projectIndex].stories[storyIndex].acceptanceCriteria.removeAll {
            $0.id == criterionID
        }
        guard persist() else {
            return .failure(.persistenceFailure(persistenceError ?? "The criterion could not be deleted"))
        }
        return .success(projects[projectIndex].stories[storyIndex])
    }

    @discardableResult
    private func persist() -> Bool {
        guard let persistenceStore else { return true }

        do {
            try persistenceStore.save(projects)
            persistenceError = nil
            return true
        } catch {
            persistenceError = error.localizedDescription
            return false
        }
    }
}

extension AppStore {
    static var preview: AppStore {
        let designer = ProjectActor(name: "Product Designer", role: "Designs product experiences")
        let developer = ProjectActor(name: "Developer", role: "Builds and ships features")
        let project = FSProject(
            name: "FS User Stories",
            prefix: "FS",
            actors: [designer, developer],
            stories: [
                UserStory(
                    number: 1,
                    title: "Create a project",
                    actorID: designer.id,
                    want: "to create a focused workspace",
                    outcome: "I can start documenting product requirements",
                    acceptanceCriteria: [
                        AcceptanceCriterion(text: "The project has a name and story prefix"),
                        AcceptanceCriterion(text: "The new project opens automatically")
                    ]
                ),
                UserStory(
                    number: 2,
                    title: "Read stories through MCP",
                    actorID: developer.id,
                    want: "an agent to read the current stories",
                    outcome: "implementation stays aligned with the requirements",
                    acceptanceCriteria: [
                        AcceptanceCriterion(text: "The agent can list local projects"),
                        AcceptanceCriterion(text: "The agent can read a complete story")
                    ],
                    status: .active
                )
            ]
        )

        return AppStore(projects: [project])
    }
}
