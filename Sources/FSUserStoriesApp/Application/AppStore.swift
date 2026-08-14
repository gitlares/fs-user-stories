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
    private(set) var projectSyncStates: [UUID: ProjectSyncState] = [:]
    private(set) var pendingSyncConflicts: [CoreSyncConflict] = []
    var selectedProjectID: UUID?
    var selectedStoryID: UUID?
    var pendingWorkspaceAction: WorkspaceAction?
    let persistenceStore: PersistenceStore?
    private let attachmentStorage: AttachmentStorage?
    private let gitSyncService: GitSyncService?
    private let gitHubService: GitHubService
    @ObservationIgnored private var sessionGitHubAccessToken: String?
    @ObservationIgnored private var localMCPServer: RustMCPServer?
    @ObservationIgnored private var localChangeVersions: [UUID: UInt] = [:]
    @ObservationIgnored private var synchronizingProjectIDs = Set<UUID>()
    @ObservationIgnored private var blockedSyncProjectIDs = Set<UUID>()
    @ObservationIgnored private var automaticMaintenanceTask: Task<Void, Never>?
    @ObservationIgnored private var mcpWorkspaceRefreshTask: Task<Void, Never>?
    @ObservationIgnored private lazy var syncScheduler = ProjectSyncScheduler { [weak self] projectID in
        guard let self else { return .blocked }
        return await self.runScheduledSynchronization(for: projectID)
    }

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
        store.startMCPWorkspaceRefresh()
        store.ensureManagedRepositories()
        store.startAutomaticSynchronization()
        return store
    }

    var mcpServerURL: URL {
        localMCPServer?.endpointURL ?? URL(
            string: "http://127.0.0.1:\(RustMCPServer.defaultPort)/mcp"
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
        do {
            guard let persistenceStore, let attachmentStorage else { return }
            let server = RustMCPServer(
                databaseURL: persistenceStore.databaseURL,
                attachmentsRootURL: attachmentStorage.rootURL,
                coreExecutableURL: try RustCoreClient().executableURL,
                stateChanged: { [weak self] state in self?.mcpServerState = state }
            )
            localMCPServer = server
            mcpServerState = .starting
            try server.start()
        } catch {
            mcpServerState = .failed(error.localizedDescription)
        }
    }

    /// MCP mutations are committed directly by Rust to the same SQLite database.
    /// Refreshing is deliberately lightweight and never queues, delays, or owns local saves.
    private func startMCPWorkspaceRefresh() {
        guard persistenceStore != nil else { return }
        mcpWorkspaceRefreshTask?.cancel()
        mcpWorkspaceRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, let persistenceStore = self.persistenceStore else { return }
                guard let refreshedProjects = try? persistenceStore.loadProjects(),
                      refreshedProjects != self.projects else { continue }
                self.projects = refreshedProjects
                if let selectedProjectID = self.selectedProjectID,
                   !refreshedProjects.contains(where: { $0.id == selectedProjectID }) {
                    self.selectedProjectID = refreshedProjects.first?.id
                    self.selectedStoryID = refreshedProjects.first?.stories.first?.id
                }
            }
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

    func syncState(for projectID: UUID) -> ProjectSyncState {
        projectSyncStates[projectID] ?? .idle
    }

    private func setSyncState(_ state: ProjectSyncState, for projectID: UUID) {
        projectSyncState = state
        projectSyncStates[projectID] = state
    }

    @discardableResult
    func createProject(name: String, prefix: String) -> Result<FSProject, WorkspaceError> {
        do {
            let project: FSProject
            if let persistenceStore {
                project = try persistenceStore.createProject(name: name, prefix: prefix)
                projects.append(project)
            } else {
                let seed = FSProject(name: "", prefix: "")
                project = try RustWorkspaceClient().apply(
                    project: seed,
                    operation: ["operation": "update_project", "name": name, "prefix": prefix]
                )
                projects.append(project)
            }
            selectedProjectID = project.id
            selectedStoryID = nil
            if let gitSyncService, let persistenceStore, let attachmentStorage {
                projects[projects.count - 1] = try gitSyncService.initializeStored(
                    projectID: project.id,
                    databaseURL: persistenceStore.databaseURL,
                    attachmentsRootURL: attachmentStorage.rootURL
                )
            }
            return .success(projects[projects.count - 1])
        } catch let error as RustCoreError {
            return .failure(workspaceError(for: error))
        } catch let error as WorkspaceError {
            return .failure(error)
        } catch {
            return .failure(.persistenceFailure(error.localizedDescription))
        }
    }

    @discardableResult
    func updateProject(
        _ projectID: UUID,
        name: String,
        prefix: String
    ) -> Result<FSProject, WorkspaceError> {
        switch mutateWorkspaceProject(
            projectID: projectID,
            operation: ["operation": "update_project", "name": name, "prefix": prefix],
            persistenceMessage: "The project could not be saved"
        ) {
        case let .success(project):
            return .success(project)
        case let .failure(error):
            return .failure(error)
        }
    }

    @discardableResult
    func deleteProject(_ projectID: UUID) -> Result<Void, WorkspaceError> {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        do {
            if let persistenceStore {
                guard let attachmentStorage else {
                    throw WorkspaceError.persistenceFailure("The local workspace is unavailable")
                }
                let repositoriesRootURL = gitSyncService?.managedRepositoriesRootURL
                    ?? attachmentStorage.rootURL
                    .deletingLastPathComponent()
                    .appending(path: "Repositories", directoryHint: .isDirectory)
                try persistenceStore.deleteProject(
                    projectID,
                    attachmentsRootURL: attachmentStorage.rootURL,
                    repositoriesRootURL: repositoriesRootURL
                )
            }
            projects.remove(at: projectIndex)
            selectedProjectID = projects.first?.id
            selectedStoryID = projects.first?.stories.first?.id
            if persistenceStore == nil, !persist() {
                return .failure(.persistenceFailure(persistenceError ?? "The project could not be deleted"))
            }
        } catch let error as RustCoreError {
            return .failure(workspaceError(for: error))
        } catch {
            return .failure(.persistenceFailure(error.localizedDescription))
        }

        projectSyncStates[projectID] = nil
        blockedSyncProjectIDs.remove(projectID)
        synchronizingProjectIDs.remove(projectID)
        return .success(())
    }

    func connectSharedRepository(remoteURL: String, projectID: UUID) async -> Result<Void, WorkspaceError> {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard let gitSyncService else {
            return .failure(.persistenceFailure("The synchronization core is unavailable"))
        }
        guard let persistenceStore, let attachmentStorage else {
            return .failure(.persistenceFailure("The local workspace is unavailable"))
        }
        let databaseURL = persistenceStore.databaseURL
        let attachmentsRootURL = attachmentStorage.rootURL
        setSyncState(.working, for: projectID)
        do {
            if projects[projectIndex].gitRepository == nil {
                projects[projectIndex] = try await Task.detached {
                    try gitSyncService.initializeStored(
                        projectID: projectID,
                        databaseURL: databaseURL,
                        attachmentsRootURL: attachmentsRootURL
                    )
                }.value
            }
            let connectedProject = try await Task.detached {
                try gitSyncService.connectStored(
                    projectID: projectID,
                    databaseURL: databaseURL,
                    attachmentsRootURL: attachmentsRootURL,
                    remoteURL: remoteURL
                )
            }.value
            guard let currentIndex = projects.firstIndex(where: { $0.id == projectID }) else {
                return .failure(.projectNotFound)
            }
            projects[currentIndex] = connectedProject
            setSyncState(.idle, for: projectID)
            return .success(())
        } catch {
            setSyncState(.failed(error.localizedDescription), for: projectID)
            return .failure(.persistenceFailure(error.localizedDescription))
        }
    }

    func prepareManagedRepository(_ projectID: UUID) async -> Result<Void, WorkspaceError> {
        guard projects.contains(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard let gitSyncService else {
            return .failure(.persistenceFailure("The synchronization core is unavailable"))
        }
        guard let persistenceStore, let attachmentStorage else {
            return .failure(.persistenceFailure("The local workspace is unavailable"))
        }
        let databaseURL = persistenceStore.databaseURL
        let attachmentsRootURL = attachmentStorage.rootURL
        setSyncState(.working, for: projectID)
        do {
            let updated = try await Task.detached {
                try gitSyncService.initializeStored(
                    projectID: projectID,
                    databaseURL: databaseURL,
                    attachmentsRootURL: attachmentsRootURL
                )
            }.value
            guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
                return .failure(.projectNotFound)
            }
            projects[projectIndex] = updated
            setSyncState(.idle, for: projectID)
            return .success(())
        } catch {
            setSyncState(.failed(error.localizedDescription), for: projectID)
            return .failure(.persistenceFailure(error.localizedDescription))
        }
    }

    func resolveProjectSynchronization(
        _ projectID: UUID,
        choices: [String: Bool]
    ) async -> Result<Void, WorkspaceError> {
        guard projects.contains(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard choices.count == pendingSyncConflicts.count else {
            return .failure(.persistenceFailure(L10n.string("Choose a version for every conflict.")))
        }
        guard let gitSyncService else {
            return .failure(.persistenceFailure("The synchronization core is unavailable"))
        }
        guard let persistenceStore, let attachmentStorage else {
            return .failure(.persistenceFailure("The local workspace is unavailable"))
        }
        let databaseURL = persistenceStore.databaseURL
        let attachmentsRootURL = attachmentStorage.rootURL
        let accessToken = githubAccessToken()
        setSyncState(.working, for: projectID)
        do {
            let synchronizedProject = try await Task.detached {
                try gitSyncService.resolveStoredSynchronization(
                    projectID: projectID,
                    choices: choices,
                    databaseURL: databaseURL,
                    attachmentsRootURL: attachmentsRootURL,
                    accessToken: accessToken
                )
            }.value
            guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
                return .failure(.projectNotFound)
            }
            projects[projectIndex] = synchronizedProject
            pendingSyncConflicts = []
            blockedSyncProjectIDs.remove(projectID)
            setSyncState(.succeeded(synchronizedProject.gitRepository?.lastSyncedAt ?? .now), for: projectID)
            return .success(())
        } catch {
            setSyncState(.failed(error.localizedDescription), for: projectID)
            return .failure(.persistenceFailure(error.localizedDescription))
        }
    }

    func synchronizeProject(_ projectID: UUID) async -> Result<Void, WorkspaceError> {
        guard projects.contains(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        guard let gitSyncService else {
            return .failure(.persistenceFailure("The synchronization core is unavailable"))
        }
        guard let persistenceStore, let attachmentStorage else {
            return .failure(.persistenceFailure("The local workspace is unavailable"))
        }
        let databaseURL = persistenceStore.databaseURL
        let attachmentsRootURL = attachmentStorage.rootURL
        guard synchronizingProjectIDs.insert(projectID).inserted else {
            return .success(())
        }
        defer { synchronizingProjectIDs.remove(projectID) }
        let accessToken = githubAccessToken()
        setSyncState(.working, for: projectID)
        do {
            let synchronizedProject = try await Task.detached {
                try gitSyncService.synchronizeStored(
                    projectID: projectID,
                    databaseURL: databaseURL,
                    attachmentsRootURL: attachmentsRootURL,
                    accessToken: accessToken
                )
            }.value
            guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
                return .failure(.projectNotFound)
            }
            projects[projectIndex] = synchronizedProject
            setSyncState(.succeeded(synchronizedProject.gitRepository?.lastSyncedAt ?? .now), for: projectID)
            return .success(())
        } catch let RustCoreError.syncConflicts(conflicts) {
            pendingSyncConflicts = conflicts
            blockedSyncProjectIDs.insert(projectID)
            setSyncState(.failed(L10n.string("Some shared changes need your decision.")), for: projectID)
            return .failure(.persistenceFailure(L10n.string("Some shared changes need your decision.")))
        } catch {
            setSyncState(.failed(error.localizedDescription), for: projectID)
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
        guard let persistenceStore, let attachmentStorage else {
            return .failure(.persistenceFailure("The local workspace is unavailable"))
        }
        let databaseURL = persistenceStore.databaseURL
        let attachmentsRootURL = attachmentStorage.rootURL
        setSyncState(.working, for: projectID)
        do {
            let project = projects[projectIndex]
            if project.gitRepository == nil {
                projects[projectIndex] = try await Task.detached {
                    try gitSyncService.initializeStored(
                        projectID: projectID,
                        databaseURL: databaseURL,
                        attachmentsRootURL: attachmentsRootURL
                    )
                }.value
            }
            let token = try await gitHubService.finishAuthorization(authorization)
            sessionGitHubAccessToken = token
            let repository = try await gitHubService.createPrivateRepository(
                name: project.name,
                token: token
            )
            _ = try await Task.detached {
                try gitSyncService.connectStored(
                    projectID: projectID,
                    databaseURL: databaseURL,
                    attachmentsRootURL: attachmentsRootURL,
                    remoteURL: repository.cloneURL
                )
            }.value
            let synchronizedProject = try await Task.detached {
                try gitSyncService.synchronizeStored(
                    projectID: projectID,
                    databaseURL: databaseURL,
                    attachmentsRootURL: attachmentsRootURL,
                    accessToken: token
                )
            }.value
            guard let currentIndex = projects.firstIndex(where: { $0.id == projectID }) else {
                return .failure(.projectNotFound)
            }
            projects[currentIndex] = synchronizedProject
            setSyncState(.succeeded(.now), for: projectID)
            return .success(repository)
        } catch {
            setSyncState(.failed(error.localizedDescription), for: projectID)
            return .failure(.persistenceFailure(error.localizedDescription))
        }
    }

    func joinSharedProject(invitation: String) async -> Result<FSProject, WorkspaceError> {
        guard let gitSyncService else {
            return .failure(.persistenceFailure("The synchronization core is unavailable"))
        }
        guard let persistenceStore, let attachmentStorage else {
            return .failure(.persistenceFailure("The local workspace is unavailable"))
        }
        let databaseURL = persistenceStore.databaseURL
        let attachmentsRootURL = attachmentStorage.rootURL
        let accessToken = githubAccessToken()
        projectSyncState = .working
        do {
            let project = try await Task.detached {
                try gitSyncService.joinStored(
                    invitation: invitation,
                    databaseURL: databaseURL,
                    attachmentsRootURL: attachmentsRootURL,
                    accessToken: accessToken
                )
            }.value
            projects.append(project)
            selectedProjectID = project.id
            selectedStoryID = project.stories.sorted { $0.createdAt > $1.createdAt }.first?.id
            projectSyncState = .succeeded(.now)
            projectSyncStates[project.id] = .succeeded(.now)
            return .success(project)
        } catch {
            projectSyncState = .failed(error.localizedDescription)
            return .failure(.persistenceFailure(error.localizedDescription))
        }
    }

    func sharedRepositoryUsesGitHub(_ remoteURL: String) -> Bool {
        guard let gitSyncService else { return false }
        return (try? gitSyncService.remoteUsesGitHub(remoteURL)) == true
    }

    func joinSharedRepository(remoteURL: String) async -> Result<FSProject, WorkspaceError> {
        guard let gitSyncService else {
            return .failure(.persistenceFailure("The synchronization core is unavailable"))
        }
        guard let persistenceStore, let attachmentStorage else {
            return .failure(.persistenceFailure("The local workspace is unavailable"))
        }
        let databaseURL = persistenceStore.databaseURL
        let attachmentsRootURL = attachmentStorage.rootURL
        let accessToken = githubAccessToken()
        projectSyncState = .working
        do {
            let project = try await Task.detached {
                try gitSyncService.joinStored(
                    remoteURL: remoteURL,
                    databaseURL: databaseURL,
                    attachmentsRootURL: attachmentsRootURL,
                    accessToken: accessToken
                )
            }.value
            projects.append(project)
            selectedProjectID = project.id
            selectedStoryID = project.stories.sorted { $0.createdAt > $1.createdAt }.first?.id
            setSyncState(.succeeded(.now), for: project.id)
            return .success(project)
        } catch {
            projectSyncState = .failed(error.localizedDescription)
            return .failure(.persistenceFailure(error.localizedDescription))
        }
    }

    private func ensureManagedRepositories() {
        guard let gitSyncService, let persistenceStore, let attachmentStorage else { return }
        for index in projects.indices where projects[index].gitRepository == nil {
            do {
                projects[index] = try gitSyncService.initializeStored(
                    projectID: projects[index].id,
                    databaseURL: persistenceStore.databaseURL,
                    attachmentsRootURL: attachmentStorage.rootURL
                )
            } catch {
                projectSyncState = .failed(error.localizedDescription)
            }
        }
    }

    func selectStory(_ storyID: UUID, in projectID: UUID) {
        selectedProjectID = projectID
        selectedStoryID = storyID
        selectedProjectDidChange()
    }

    func selectedProjectDidChange() {
        guard let selectedProject else { return }
        syncScheduler.projectBecameActive(selectedProject)
    }

    func applicationDidBecomeActive() {
        selectedProjectDidChange()
    }

    private func startAutomaticSynchronization() {
        selectedProjectDidChange()
        automaticMaintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: ProjectSyncScheduler.Policy.production.maintenanceInterval)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                scheduleDueProjectRefreshes()
            }
        }
    }

    private func scheduleDueProjectRefreshes() {
        let activeProject = selectedProject
        let inactiveProjects = projects.filter { $0.id != activeProject?.id }
        syncScheduler.scheduleMaintenance(
            activeProject: activeProject,
            inactiveProjects: inactiveProjects
        )
    }

    private func runScheduledSynchronization(for projectID: UUID) async -> ProjectSyncScheduler.AttemptOutcome {
        guard
            let project = projects.first(where: { $0.id == projectID }),
            project.gitRepository?.remoteURL != nil
        else {
            return .blocked
        }
        guard !blockedSyncProjectIDs.contains(projectID) else {
            return .blocked
        }
        switch await synchronizeProject(projectID) {
        case .success:
            return .succeeded
        case .failure:
            return .retryLater
        }
    }

    func requestStoryCreation(in projectID: UUID) {
        selectedProjectID = projectID
        selectedStoryID = nil
        pendingWorkspaceAction = .createStory(projectID: projectID)
    }

    @discardableResult
    func addActor(name: String, role: String, to projectID: UUID) -> Result<ProjectActor, WorkspaceError> {
        switch mutateWorkspaceProject(
            projectID: projectID,
            operation: ["operation": "add_actor", "name": name, "role": role],
            persistenceMessage: "The actor could not be saved"
        ) {
        case let .success(project):
            guard let actor = project.actors.last else { return .failure(.actorNotFound) }
            return .success(actor)
        case let .failure(error):
            return .failure(error)
        }
    }

    @discardableResult
    func updateActor(
        _ actorID: UUID,
        name: String,
        role: String,
        projectID: UUID
    ) -> Result<ProjectActor, WorkspaceError> {
        switch mutateWorkspaceProject(
            projectID: projectID,
            operation: [
                "operation": "update_actor",
                "actor_id": actorID.uuidString,
                "name": name,
                "role": role
            ],
            persistenceMessage: "The actor could not be saved"
        ) {
        case let .success(project):
            guard let actor = project.actors.first(where: { $0.id == actorID }) else {
                return .failure(.actorNotFound)
            }
            return .success(actor)
        case let .failure(error):
            return .failure(error)
        }
    }

    @discardableResult
    func deleteActor(_ actorID: UUID, projectID: UUID) -> Result<Void, WorkspaceError> {
        switch mutateWorkspaceProject(
            projectID: projectID,
            operation: ["operation": "delete_actor", "actor_id": actorID.uuidString],
            persistenceMessage: "The actor could not be deleted"
        ) {
        case .success:
            return .success(())
        case let .failure(error):
            return .failure(error)
        }
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
        switch mutateWorkspaceProject(
            projectID: projectID,
            operation: [
                "operation": "add_story",
                "title": title,
                "actor_id": actorID.uuidString,
                "want": want,
                "outcome": outcome,
                "acceptance_criteria": coreCriteria(acceptanceCriteria)
            ],
            persistenceMessage: "The story could not be saved"
        ) {
        case let .success(project):
            guard let story = project.stories.last else { return .failure(.storyNotFound) }
            selectedStoryID = story.id
            return .success(story)
        case let .failure(error):
            return .failure(error)
        }
    }

    @discardableResult
    func importStories(
        _ importedStories: [PortableStory],
        to projectID: UUID
    ) -> Result<Int, WorkspaceError> {
        guard !importedStories.isEmpty else { return .success(0) }
        guard let currentProject = projects.first(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }
        do {
            let encodedStories = try coreJSONObject(importedStories)
            switch mutateWorkspaceProject(
                projectID: projectID,
                operation: [
                    "operation": "import_stories",
                    "stories": encodedStories,
                    "imported_profile_name": L10n.string("Imported Profile")
                ],
                persistenceMessage: L10n.string("The stories could not be imported.")
            ) {
            case let .success(project):
                selectedStoryID = project.stories.dropFirst(currentProject.stories.count).last?.id
                return .success(importedStories.count)
            case let .failure(error):
                return .failure(error)
            }
        } catch {
            return .failure(.persistenceFailure(error.localizedDescription))
        }
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
        switch mutateWorkspaceProject(
            projectID: projectID,
            operation: [
                "operation": "update_story",
                "story_id": storyID.uuidString,
                "title": title,
                "actor_id": actorID.uuidString,
                "want": want,
                "outcome": outcome,
                "acceptance_criteria": coreCriteria(acceptanceCriteria)
            ],
            persistenceMessage: "The story could not be saved"
        ) {
        case let .success(project):
            guard let story = project.stories.first(where: { $0.id == storyID }) else {
                return .failure(.storyNotFound)
            }
            return .success(story)
        case let .failure(error):
            return .failure(error)
        }
    }

    @discardableResult
    func toggleAcceptanceCriterion(
        _ criterionID: UUID,
        in storyID: UUID,
        projectID: UUID
    ) -> Result<UserStory, WorkspaceError> {
        applyWorkspaceOperation(
            storyID: storyID,
            projectID: projectID,
            operation: [
                "operation": "toggle_acceptance_criterion",
                "story_id": storyID.uuidString,
                "criterion_id": criterionID.uuidString
            ],
            persistenceMessage: "The criterion could not be saved"
        )
    }

    @discardableResult
    func setAcceptanceCriterion(
        _ criterionID: UUID,
        isMet: Bool,
        in storyID: UUID,
        projectID: UUID
    ) -> Result<UserStory, WorkspaceError> {
        applyWorkspaceOperation(
            storyID: storyID,
            projectID: projectID,
            operation: [
                "operation": "set_acceptance_criterion",
                "story_id": storyID.uuidString,
                "criterion_id": criterionID.uuidString,
                "is_met": isMet
            ],
            persistenceMessage: "The criterion could not be saved"
        )
    }

    @discardableResult
    func addAcceptanceCriterion(
        text: String,
        to storyID: UUID,
        projectID: UUID
    ) -> Result<UserStory, WorkspaceError> {
        applyWorkspaceOperation(
            storyID: storyID,
            projectID: projectID,
            operation: [
                "operation": "add_acceptance_criterion",
                "story_id": storyID.uuidString,
                "text": text
            ],
            persistenceMessage: "The criterion could not be saved"
        )
    }

    @discardableResult
    func setStoryStatus(
        _ status: StoryStatus,
        for storyID: UUID,
        projectID: UUID
    ) -> Result<UserStory, WorkspaceError> {
        applyWorkspaceOperation(
            storyID: storyID,
            projectID: projectID,
            operation: [
                "operation": "set_story_status",
                "story_id": storyID.uuidString,
                "status": status.rawValue
            ],
            persistenceMessage: "The story status could not be saved"
        )
    }

    @discardableResult
    func duplicateStory(_ storyID: UUID, projectID: UUID) -> Result<UserStory, WorkspaceError> {
        guard let source = projects.first(where: { $0.id == projectID })?.stories.first(where: { $0.id == storyID }) else {
            return .failure(.storyNotFound)
        }
        switch mutateWorkspaceProject(
            projectID: projectID,
            operation: [
                "operation": "duplicate_story",
                "story_id": storyID.uuidString,
                "copy_title": String(format: L10n.string("Copy of %@"), source.title)
            ],
            persistenceMessage: "The story could not be duplicated"
        ) {
        case let .success(project):
            guard let story = project.stories.last else { return .failure(.storyNotFound) }
            selectedStoryID = story.id
            return .success(story)
        case let .failure(error):
            return .failure(error)
        }
    }

    @discardableResult
    func updateStoryNotes(
        _ notes: String,
        for storyID: UUID,
        projectID: UUID
    ) -> Result<UserStory, WorkspaceError> {
        applyWorkspaceOperation(
            storyID: storyID,
            projectID: projectID,
            operation: [
                "operation": "update_story_notes",
                "story_id": storyID.uuidString,
                "notes": notes
            ],
            persistenceMessage: "The notes could not be saved"
        )
    }

    @discardableResult
    func deleteStory(_ storyID: UUID, projectID: UUID) -> Result<Void, WorkspaceError> {
        if let persistenceStore, let attachmentStorage,
           let projectIndex = projects.firstIndex(where: { $0.id == projectID }) {
            do {
                let project = try persistenceStore.deleteStory(
                    storyID,
                    projectID: projectID,
                    attachmentsRootURL: attachmentStorage.rootURL
                )
                projects[projectIndex] = project
                if selectedStoryID == storyID {
                    selectedStoryID = project.stories.first?.id
                }
                recordPersistedChange(for: projectID)
                return .success(())
            } catch let error as RustCoreError {
                return .failure(workspaceError(for: error))
            } catch {
                return .failure(.persistenceFailure(error.localizedDescription))
            }
        }
        switch mutateWorkspaceProject(
            projectID: projectID,
            operation: ["operation": "delete_story", "story_id": storyID.uuidString],
            persistenceMessage: "The story could not be deleted"
        ) {
        case let .success(project):
            if selectedStoryID == storyID {
                let remainingStories = project.stories
                selectedStoryID = remainingStories.first?.id
            }
            return .success(())
        case let .failure(error):
            return .failure(error)
        }
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
        guard let attachmentStorage, let persistenceStore else {
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
        do {
            let updatedProject = try attachmentStorage.withSecurityScopedAccess(to: urls) {
                try persistenceStore.importAttachments(
                    sourceURLs: urls,
                    projectID: projectID,
                    storyID: storyID,
                    attachmentsRootURL: attachmentStorage.rootURL
                )
            }
            projects[projectIndex] = updatedProject
            recordPersistedChange(for: projectID)
            guard let updatedStory = updatedProject.stories.first(where: { $0.id == storyID }) else {
                return .failure(.storyNotFound)
            }
            return .success(updatedStory)
        } catch let error as RustCoreError {
            return .failure(workspaceError(for: error))
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
        guard projects[projectIndex].stories.contains(where: { $0.id == storyID }) else {
            return .failure(.storyNotFound)
        }
        guard let persistenceStore else {
            return .failure(.persistenceFailure("The local workspace is unavailable"))
        }
        do {
            projects[projectIndex] = try persistenceStore.removeAttachment(
                attachmentID: attachmentID,
                projectID: projectID,
                storyID: storyID,
                attachmentsRootURL: attachmentStorage.rootURL
            )
            recordPersistedChange(for: projectID)
            return .success(())
        } catch let error as RustCoreError {
            return .failure(workspaceError(for: error))
        } catch {
            return .failure(.attachmentFailure(error.localizedDescription))
        }
    }

    @discardableResult
    func deleteAcceptanceCriterion(
        _ criterionID: UUID,
        from storyID: UUID,
        projectID: UUID
    ) -> Result<UserStory, WorkspaceError> {
        applyWorkspaceOperation(
            storyID: storyID,
            projectID: projectID,
            operation: [
                "operation": "delete_acceptance_criterion",
                "story_id": storyID.uuidString,
                "criterion_id": criterionID.uuidString
            ],
            persistenceMessage: "The criterion could not be deleted"
        )
    }

    private func applyWorkspaceOperation(
        storyID: UUID,
        projectID: UUID,
        operation: [String: Any],
        persistenceMessage: String
    ) -> Result<UserStory, WorkspaceError> {
        switch mutateWorkspaceProject(
            projectID: projectID,
            operation: operation,
            persistenceMessage: persistenceMessage
        ) {
        case let .success(project):
            guard let story = project.stories.first(where: { $0.id == storyID }) else {
                return .failure(.storyNotFound)
            }
            return .success(story)
        case let .failure(error):
            return .failure(error)
        }
    }

    private func mutateWorkspaceProject(
        projectID: UUID,
        operation: [String: Any],
        persistenceMessage: String
    ) -> Result<FSProject, WorkspaceError> {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return .failure(.projectNotFound)
        }

        do {
            let updatedProject: FSProject
            if let persistenceStore {
                // The Rust core reads, mutates, and commits the sole SQLite database
                // in one operation. Swift only replaces its rendered snapshot.
                updatedProject = try persistenceStore.applyWorkspaceOperation(
                    projectID: projectID,
                    operation: operation
                )
            } else {
                updatedProject = try RustWorkspaceClient().apply(
                    project: projects[projectIndex],
                    operation: operation
                )
            }
            projects[projectIndex] = updatedProject
            if persistenceStore != nil {
                recordPersistedChange(for: projectID)
            } else if !persist(changedProjectID: projectID) {
                return .failure(.persistenceFailure(persistenceError ?? persistenceMessage))
            }
            return .success(updatedProject)
        } catch let error as RustCoreError {
            return .failure(workspaceError(for: error))
        } catch {
            return .failure(.persistenceFailure(error.localizedDescription))
        }
    }

    private func coreCriteria(_ criteria: [AcceptanceCriterion]) -> [[String: Any]] {
        criteria.map {
            [
                "id": $0.id.uuidString,
                "text": $0.text,
                "isMet": $0.isMet
            ]
        }
    }

    private func coreJSONObject<T: Encodable>(_ value: T) throws -> Any {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try JSONSerialization.jsonObject(with: encoder.encode(value))
    }

    private func workspaceError(for error: RustCoreError) -> WorkspaceError {
        guard case let .coreFailure(code, message) = error else {
            return .persistenceFailure(error.localizedDescription)
        }

        let mappedError: WorkspaceError = switch code {
        case "workspace_story_not_found": .storyNotFound
        case "workspace_project_not_found": .projectNotFound
        case "workspace_actor_not_found": .actorNotFound
        case "workspace_actor_in_use": .actorInUse
        case "workspace_name_required": .nameRequired
        case "workspace_prefix_required": .prefixRequired
        case "workspace_story_title_required": .titleRequired
        case "workspace_story_want_required": .wantRequired
        case "workspace_story_outcome_required": .outcomeRequired
        case "workspace_attachments_required": .attachmentsRequired
        case "workspace_attachment_not_found": .attachmentNotFound
        case "workspace_attachment_limit": .attachmentFailure(L10n.string("A story can have up to 10 attachments."))
        case "workspace_attachment_size_limit": .attachmentFailure(L10n.string("Attachments for a story cannot exceed 50 MB."))
        case "workspace_criterion_not_found": .criterionNotFound
        case "completed_story_read_only": .completedStoryReadOnly
        case "incomplete_acceptance_criteria": .incompleteAcceptanceCriteria
        case "acceptance_criterion_required": .acceptanceCriterionRequired
        default: .persistenceFailure(message)
        }
        return mappedError
    }

    @discardableResult
    private func persist(changedProjectID: UUID? = nil) -> Bool {
        guard let persistenceStore else { return true }

        do {
            // SQLite is the source of truth. A remote sync is only scheduled
            // after this write succeeds and can never hold up local editing.
            try persistenceStore.save(projects)
            if let changedProjectID {
                recordPersistedChange(for: changedProjectID)
            } else {
                persistenceError = nil
            }
            return true
        } catch {
            persistenceError = error.localizedDescription
            return false
        }
    }

    private func recordPersistedChange(for projectID: UUID) {
        persistenceError = nil
        guard let project = projects.first(where: { $0.id == projectID }),
              project.gitRepository?.remoteURL != nil else {
            return
        }
        localChangeVersions[projectID, default: 0] &+= 1
        syncScheduler.recordLocalChange(for: projectID)
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
