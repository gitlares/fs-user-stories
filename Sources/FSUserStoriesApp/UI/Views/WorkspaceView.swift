// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum PresentedSheet: Identifiable {
    case newProject
    case newActor(projectID: UUID)
    case editActor(projectID: UUID, actorID: UUID)
    case newStory(projectID: UUID)
    case editStory(projectID: UUID, storyID: UUID)
    case sharing(projectID: UUID)
    case joinSharedProject
    case connectExistingRepository
    case exportStories(projectID: UUID)
    case importStories(projectID: UUID, document: StoryMarkdownDocument)

    var id: String {
        switch self {
        case .newProject:
            "new-project"
        case let .newActor(projectID):
            "new-actor-\(projectID)"
        case let .editActor(projectID, actorID):
            "edit-actor-\(projectID)-\(actorID)"
        case let .newStory(projectID):
            "new-story-\(projectID)"
        case let .editStory(projectID, storyID):
            "edit-story-\(projectID)-\(storyID)"
        case let .sharing(projectID):
            "sharing-\(projectID)"
        case .joinSharedProject:
            "join-shared-project"
        case .connectExistingRepository:
            "connect-existing-repository"
        case let .exportStories(projectID):
            "export-stories-\(projectID)"
        case let .importStories(projectID, document):
            "import-stories-\(projectID)-\(document.stories.count)"
        }
    }
}

private enum ProjectArea: String, CaseIterable, Identifiable {
    case stories
    case profiles

    var id: Self { self }
}

struct WorkspaceView: View {
    @Bindable var store: AppStore
    @State private var presentedSheet: PresentedSheet?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var storyPendingDeletion: UserStory?
    @State private var projectArea: ProjectArea = .stories
    @State private var selectedProfileID: UUID?

    var body: some View {
        Group {
            if store.selectedProject == nil {
                NavigationStack {
                    WelcomeView(
                        createProject: { presentedSheet = .newProject },
                        joinWithInvitation: { presentedSheet = .joinSharedProject },
                        connectRepository: { presentedSheet = .connectExistingRepository }
                    )
                    .navigationTitle(L10n.string("Projects"))
                }
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    projectSidebar
                } content: {
                    storiesColumn
                } detail: {
                    storyDetail
                }
            }
        }
        .navigationTitle(store.selectedProject?.name ?? "Projects")
        .focusedSceneValue(\.workspaceCommandActions, workspaceCommandActions)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let project = store.selectedProject {
                    if project.gitRepository?.remoteURL != nil {
                        ProjectSyncIndicator(
                            state: store.syncState(for: project.id),
                            lastSyncedAt: project.gitRepository?.lastSyncedAt
                        )
                    }

                    Button {
                        presentedSheet = .sharing(projectID: project.id)
                    } label: {
                        Label(L10n.string("Share & Sync"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .help(L10n.string("Share & Sync"))

                    Button {
                        presentedSheet = .newActor(projectID: project.id)
                    } label: {
                        Label(L10n.string("Add Profile"), systemImage: "person.badge.plus")
                    }
                    .help(L10n.string("Add Profile"))

                    Button {
                        presentedSheet = .newStory(projectID: project.id)
                    } label: {
                        Label(L10n.string("Add Story"), systemImage: "square.and.pencil")
                    }
                    .help(project.actors.isEmpty ? L10n.string("Add an actor first") : L10n.string("Add Story"))
                    .disabled(project.actors.isEmpty)
                }
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .newProject:
                NewProjectSheet { name, prefix in
                    store.createProject(name: name, prefix: prefix)
                }
            case let .newActor(projectID):
                NewActorSheet { name, role in
                    store.addActor(name: name, role: role, to: projectID)
                }
            case let .editActor(projectID, actorID):
                if
                    let project = store.projects.first(where: { $0.id == projectID }),
                    let actor = project.actors.first(where: { $0.id == actorID })
                {
                    NewActorSheet(profile: actor) { name, role in
                        store.updateActor(
                            actorID,
                            name: name,
                            role: role,
                            projectID: projectID
                        )
                    }
                }
            case let .newStory(projectID):
                if let project = store.projects.first(where: { $0.id == projectID }) {
                    NewStorySheet(actors: project.actors) { title, actorID, want, outcome, criteria in
                        store.addStory(
                            title: title,
                            actorID: actorID,
                            want: want,
                            outcome: outcome,
                            acceptanceCriteria: criteria,
                            to: projectID
                        )
                    }
                }
            case let .editStory(projectID, storyID):
                if
                    let project = store.projects.first(where: { $0.id == projectID }),
                    let story = project.stories.first(where: { $0.id == storyID })
                {
                    NewStorySheet(actors: project.actors, story: story) {
                        title, actorID, want, outcome, criteria in
                        store.updateStory(
                            storyID,
                            title: title,
                            actorID: actorID,
                            want: want,
                            outcome: outcome,
                            acceptanceCriteria: criteria,
                            projectID: projectID
                        )
                    }
                }
            case let .sharing(projectID):
                GitSyncView(store: store, projectID: projectID)
            case .joinSharedProject:
                GitJoinView(store: store, initialMode: .invitation)
            case .connectExistingRepository:
                GitJoinView(store: store, initialMode: .repository)
            case let .exportStories(projectID):
                if let project = store.projects.first(where: { $0.id == projectID }) {
                    StoryExportView(
                        project: project,
                        initiallySelectedStoryID: store.selectedStoryID
                    )
                }
            case let .importStories(projectID, document):
                StoryImportReviewView(document: document) { stories in
                    store.importStories(stories, to: projectID)
                }
            }
        }
        .alert(
            L10n.string("Delete Story?"),
            isPresented: keyboardDeleteConfirmationIsPresented,
            presenting: storyPendingDeletion
        ) { story in
            Button(L10n.string("Delete Story"), role: .destructive) {
                if let projectID = store.selectedProjectID {
                    store.deleteStory(story.id, projectID: projectID)
                }
                storyPendingDeletion = nil
            }
            Button(L10n.string("Cancel"), role: .cancel) {
                storyPendingDeletion = nil
            }
        } message: { _ in
            Text(
                L10n.string(
                    "Deleting this story will permanently remove it, its acceptance criteria, and its attachments. This cannot be undone."
                )
            )
        }
        .onAppear(perform: handlePendingWorkspaceAction)
        .onChange(of: store.pendingWorkspaceAction) {
            handlePendingWorkspaceAction()
        }
        .onChange(of: store.selectedProjectID) {
            store.selectedProjectDidChange()
        }
        .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
    }

    private var projectSidebar: some View {
        List(selection: $store.selectedProjectID) {
            Section(L10n.string("Projects")) {
                ForEach(store.projects) { project in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name)
                            ProjectProgressLabel(project: project)
                        }
                    } icon: {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                    }
                    .tag(project.id)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 210, ideal: 238, max: 300)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()

                MCPFooter(store: store)

                Divider()

                Button {
                    presentedSheet = .newProject
                } label: {
                    Label(L10n.string("New Project"), systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .accessibilityLabel(L10n.string("Create a new project"))

                Button {
                    presentedSheet = .joinSharedProject
                } label: {
                    Label(L10n.string("Join Shared Project"), systemImage: "person.2.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
            .background(.bar)
        }
    }

    @ViewBuilder
    private var storiesColumn: some View {
        if let project = store.selectedProject {
            VStack(spacing: 0) {
                Picker(L10n.string("Project Section"), selection: $projectArea) {
                    Label(L10n.string("Stories"), systemImage: "text.page")
                        .tag(ProjectArea.stories)
                    Label(L10n.string("Profiles"), systemImage: "person.2")
                        .tag(ProjectArea.profiles)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 260)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                Divider()

                switch projectArea {
                case .stories:
                    ProjectStoriesView(
                        project: project,
                        selectedStoryID: $store.selectedStoryID,
                        addActor: { presentedSheet = .newActor(projectID: project.id) },
                        addStory: { presentedSheet = .newStory(projectID: project.id) },
                        editStory: { storyID in
                            presentedSheet = .editStory(projectID: project.id, storyID: storyID)
                        },
                        duplicateStory: { storyID in
                            store.duplicateStory(storyID, projectID: project.id)
                        },
                        deleteStory: { storyID in
                            store.deleteStory(storyID, projectID: project.id)
                        }
                    )
                case .profiles:
                    ProjectProfilesView(
                        project: project,
                        selectedProfileID: $selectedProfileID,
                        addProfile: { presentedSheet = .newActor(projectID: project.id) },
                        editProfile: { actorID in
                            presentedSheet = .editActor(projectID: project.id, actorID: actorID)
                        },
                        deleteProfile: { actorID in
                            store.deleteActor(actorID, projectID: project.id)
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            WelcomeView(
                createProject: { presentedSheet = .newProject },
                joinWithInvitation: { presentedSheet = .joinSharedProject },
                connectRepository: { presentedSheet = .connectExistingRepository }
            )
        }
    }

    @ViewBuilder
    private var storyDetail: some View {
        if projectArea == .profiles {
            if
                let project = store.selectedProject,
                let selectedProfileID,
                let profile = project.actors.first(where: { $0.id == selectedProfileID })
            {
                ProfileDetailView(
                    profile: profile,
                    project: project,
                    editProfile: {
                        presentedSheet = .editActor(
                            projectID: project.id,
                            actorID: profile.id
                        )
                    },
                    deleteProfile: {
                        store.deleteActor(profile.id, projectID: project.id)
                        self.selectedProfileID = project.actors.first(where: { $0.id != profile.id })?.id
                    }
                )
            } else {
                ContentUnavailableView(
                    L10n.string("Select a Profile"),
                    systemImage: "person.crop.circle",
                    description: Text(L10n.string("Choose a profile to see its details."))
                )
            }
        } else if let project = store.selectedProject, let story = store.selectedStory {
            StoryDetailView(
                story: story,
                project: project,
                actor: project.actors.first { $0.id == story.actorID },
                setStatus: { status in
                    store.setStoryStatus(
                        status,
                        for: story.id,
                        projectID: project.id
                    )
                },
                toggleCriterion: { criterionID in
                    store.toggleAcceptanceCriterion(
                        criterionID,
                        in: story.id,
                        projectID: project.id
                    )
                },
                addCriterion: { text in
                    store.addAcceptanceCriterion(
                        text: text,
                        to: story.id,
                        projectID: project.id
                    )
                },
                editStory: {
                    presentedSheet = .editStory(projectID: project.id, storyID: story.id)
                },
                duplicateStory: {
                    store.duplicateStory(story.id, projectID: project.id)
                },
                deleteStory: {
                    store.deleteStory(story.id, projectID: project.id)
                },
                deleteCriterion: { criterionID in
                    store.deleteAcceptanceCriterion(
                        criterionID,
                        from: story.id,
                        projectID: project.id
                    )
                },
                updateNotes: { notes in
                    store.updateStoryNotes(
                        notes,
                        for: story.id,
                        projectID: project.id
                    )
                },
                addAttachments: { urls in
                    store.addAttachments(
                        from: urls,
                        to: story.id,
                        projectID: project.id
                    )
                },
                attachmentURL: { attachment in
                    store.attachmentURL(for: attachment)
                },
                deleteAttachment: { attachmentID in
                    store.deleteAttachment(
                        attachmentID,
                        from: story.id,
                        projectID: project.id
                    )
                }
            )
        } else if store.selectedProject != nil {
            ContentUnavailableView(
                L10n.string("Select a Story"),
                systemImage: "text.page",
                description: Text(L10n.string("Choose a story to see its details."))
            )
        } else {
            Color.clear
        }
    }

    private func handlePendingWorkspaceAction() {
        guard let action = store.pendingWorkspaceAction else { return }

        switch action {
        case let .createStory(projectID):
            presentedSheet = .newStory(projectID: projectID)
        }

        store.pendingWorkspaceAction = nil
    }

    private var workspaceCommandActions: WorkspaceCommandActions {
        WorkspaceCommandActions(
            hasSelectedProject: store.selectedProject != nil,
            canCreateStory: store.selectedProject?.actors.isEmpty == false,
            hasSelectedStory: store.selectedStory != nil,
            canEditSelectedStory: store.selectedStory?.status != .done && store.selectedStory != nil,
            createProject: {
                presentedSheet = .newProject
            },
            createStory: {
                guard
                    let project = store.selectedProject,
                    !project.actors.isEmpty
                else { return }
                presentedSheet = .newStory(projectID: project.id)
            },
            importStories: {
                chooseStoryImportFile()
            },
            exportStories: {
                guard let projectID = store.selectedProjectID else { return }
                presentedSheet = .exportStories(projectID: projectID)
            },
            editStory: {
                guard
                    let projectID = store.selectedProjectID,
                    let storyID = store.selectedStoryID
                else { return }
                presentedSheet = .editStory(projectID: projectID, storyID: storyID)
            },
            duplicateStory: {
                guard
                    let projectID = store.selectedProjectID,
                    let storyID = store.selectedStoryID
                else { return }
                store.duplicateStory(storyID, projectID: projectID)
            },
            requestStoryDeletion: {
                storyPendingDeletion = store.selectedStory
            }
        )
    }

    private func chooseStoryImportFile() {
        guard let projectID = store.selectedProjectID else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            let document = try StoryMarkdownTransfer.parse(markdown)
            presentedSheet = .importStories(projectID: projectID, document: document)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    private var keyboardDeleteConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { storyPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    storyPendingDeletion = nil
                }
            }
        )
    }
}

private struct ProjectSyncIndicator: View {
    let state: ProjectSyncState
    let lastSyncedAt: Date?

    var body: some View {
        Group {
            switch state {
            case .working:
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.string("Synchronizing…"))
                }
            case .failed:
                Label(L10n.string("Sync failed"), systemImage: "exclamationmark.icloud.fill")
                    .foregroundStyle(.red)
            case .succeeded:
                Label(L10n.string("Synchronized"), systemImage: "checkmark.icloud.fill")
                    .foregroundStyle(.green)
            case .idle:
                if lastSyncedAt != nil {
                    Label(L10n.string("Synchronized"), systemImage: "checkmark.icloud")
                        .foregroundStyle(.secondary)
                } else {
                    Label(L10n.string("Waiting to sync"), systemImage: "icloud")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption.weight(.medium))
        .help(helpText)
        .accessibilityElement(children: .combine)
    }

    private var helpText: String {
        guard let lastSyncedAt else { return L10n.string("This project has not synchronized yet.") }
        return "\(L10n.string("Last synchronized")): \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct MCPFooter: View {
    let store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)

                Text(statusTitle)
                    .font(.caption.weight(.semibold))

                Spacer()

                Button {
                    copyURL()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(store.mcpServerState != .running)
                .help(L10n.string("Copy MCP URL"))
                .accessibilityLabel(L10n.string("Copy MCP URL"))
            }

            Text(store.mcpServerURL.absoluteString)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(store.mcpServerURL.absoluteString)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private var statusTitle: String {
        switch store.mcpServerState {
        case .running:
            L10n.string("MCP Active")
        case .starting:
            L10n.string("MCP Starting…")
        case .stopped, .failed:
            L10n.string("MCP Inactive")
        }
    }

    private var statusColor: Color {
        switch store.mcpServerState {
        case .running: .green
        case .starting: .orange
        case .stopped, .failed: .secondary
        }
    }

    private func copyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.mcpServerURL.absoluteString, forType: .string)
    }
}

private struct ProjectProgressLabel: View {
    let project: FSProject

    private var completedCount: Int {
        project.stories.count { $0.status == .done }
    }

    private var progress: Double {
        guard !project.stories.isEmpty else { return 0 }
        return Double(completedCount) / Double(project.stories.count)
    }

    private var isComplete: Bool {
        !project.stories.isEmpty && completedCount == project.stories.count
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle.dotted")
                .font(.caption)
                .foregroundStyle(isComplete ? Color.green : Color.secondary)

            Text("\(completedCount)/\(project.stories.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 42)
                .tint(isComplete ? .green : .accentColor)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(
                format: L10n.string("%d of %d stories completed"),
                completedCount,
                project.stories.count
            )
        )
    }
}

struct WorkspaceView_Previews: PreviewProvider {
    static var previews: some View {
        WorkspaceView(store: .preview)
            .frame(width: 1180, height: 760)
    }
}
