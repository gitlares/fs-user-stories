// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

struct GitSyncView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: AppStore
    let projectID: UUID
    @State private var remoteURL = ""
    @State private var errorMessage: String?
    @State private var invitation: String?
    @State private var conflictChoices: [String: Bool] = [:]
    @State private var githubAuthorization: GitHubDeviceAuthorization?
    @State private var createdGitHubRepository: GitHubRepository?
    @State private var manualConnectionIsExpanded = false
    @State private var attemptedRepositoryPreparation = false
    @State private var collaboratorUsername = ""
    @State private var collaboratorInvitationSent = false

    private var project: FSProject? {
        store.projects.first { $0.id == projectID }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if let project {
                        if let link = project.gitRepository {
                            localRepository(link)
                            if let connectedURL = link.remoteURL {
                                connectedRepository(project, link: link, remoteURL: connectedURL)
                            } else {
                                connectRepository(project)
                            }
                        } else {
                            unavailableRepository(project)
                        }
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
                .padding(32)
            }

            Divider()
            HStack {
                Text(L10n.string("Git is optional. Your project always remains available locally."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.string("Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 620, height: 570)
    }

    private func unavailableRepository(_ project: FSProject) -> some View {
        ContentUnavailableView {
            Label(L10n.string("Repository unavailable"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(L10n.string("The managed local repository could not be created."))
        } actions: {
            Button {
                prepareRepository(project)
            } label: {
                Label(
                    isWorking ? L10n.string("Preparing…") : L10n.string("Try Again"),
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.glassProminent)
            .disabled(isWorking)
        }
        .onAppear {
            guard !attemptedRepositoryPreparation else { return }
            attemptedRepositoryPreparation = true
            prepareRepository(project)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 42))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("Share & Sync"))
                    .font(.title.bold())
                Text(L10n.string("Share this project through any Git hosting provider."))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func localRepository(_ link: GitRepositoryLink) -> some View {
        GroupBox {
            LabeledContent(L10n.string("Local copy")) {
                Text(link.localPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        } label: {
            Label(L10n.string("Managed Repository"), systemImage: "internaldrive")
        }
    }

    private func connectRepository(_ project: FSProject) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.string("FS User Stories will create a private GitHub repository and synchronize this project automatically."))
                        .foregroundStyle(.secondary)

                    if !store.gitHubRepositoryCreationIsConfigured {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(
                                L10n.string("Automatic GitHub creation is not configured in this development build."),
                                systemImage: "hammer"
                            )
                            .font(.callout.weight(.medium))

                            Text(L10n.string("Create an empty private repository on GitHub, copy its SSH URL, and connect it below."))
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            Link(
                                destination: githubNewRepositoryURL(for: project)
                            ) {
                                Label(L10n.string("Create Repository on GitHub…"), systemImage: "arrow.up.right.square")
                            }
                        }
                        .padding(14)
                        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    }

                    if let authorization = githubAuthorization {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L10n.string("Enter this code on GitHub"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(authorization.userCode)
                                    .font(.title2.monospaced().bold())
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            ProgressView()
                            Text(L10n.string("Waiting for authorization…"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    }

                    HStack {
                        Label(
                            L10n.string("Private by default. The token is stored in Keychain when available."),
                            systemImage: "lock.shield"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            createOnGitHub(project)
                        } label: {
                            Label(
                                githubAuthorization == nil
                                    ? L10n.string("Create on GitHub")
                                    : L10n.string("Authorizing…"),
                                systemImage: "plus.circle.fill"
                            )
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(
                            !store.gitHubRepositoryCreationIsConfigured
                                || githubAuthorization != nil
                                || isWorking
                        )
                    }
                }
            } label: {
                Label(L10n.string("Create Shared Repository"), systemImage: "shippingbox.and.arrow.backward")
            }

            DisclosureGroup(
                L10n.string("Connect another Git provider"),
                isExpanded: $manualConnectionIsExpanded
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.string("Create an empty repository with your preferred provider, grant access to your collaborators, then paste its SSH or HTTPS URL here."))
                        .foregroundStyle(.secondary)
                    TextField("git@example.com:team/project.git", text: $remoteURL)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { connect(project) }
                    HStack {
                        Label(L10n.string("SSH uses your existing local credentials."), systemImage: "key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.string("Connect")) { connect(project) }
                            .disabled(
                                remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || isWorking
                            )
                    }
                }
                .padding(.top, 10)
            }

            Label(
                L10n.string("FS User Stories only uses the isolated fs-user-stories branch. Your code branches are never modified."),
                systemImage: "shield.checkered"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onAppear {
            if !store.gitHubRepositoryCreationIsConfigured {
                manualConnectionIsExpanded = true
            }
        }
    }

    private func githubNewRepositoryURL(for project: FSProject) -> URL {
        var components = URLComponents(string: "https://github.com/new")!
        let repositoryName = project.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        components.queryItems = [
            URLQueryItem(name: "name", value: repositoryName),
            URLQueryItem(name: "description", value: "User stories shared with FS User Stories"),
            URLQueryItem(name: "visibility", value: "private")
        ]
        return components.url!
    }

    private func connectedRepository(
        _ project: FSProject,
        link: GitRepositoryLink,
        remoteURL: String
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                LabeledContent(L10n.string("Shared repository")) {
                    Text(remoteURL)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                LabeledContent(L10n.string("Last synchronized")) {
                    Text(link.lastSyncedAt?.formatted(date: .abbreviated, time: .shortened) ?? L10n.string("Not yet"))
                }
                if isGitHubURL(remoteURL) {
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.string("GitHub access"))
                            .font(.headline)
                        Text(L10n.string("Authorize this Mac again if you moved from a development build or GitHub access expired."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let authorization = githubAuthorization {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(L10n.string("Enter this code on GitHub"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(authorization.userCode)
                                        .font(.title2.monospaced().bold())
                                        .textSelection(.enabled)
                                }
                                Spacer()
                                ProgressView()
                                Text(L10n.string("Waiting for GitHub authorization…"))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        }
                        HStack {
                            Label(
                                store.gitHubIsAuthorized
                                    ? L10n.string("GitHub is authorized on this Mac.")
                                    : L10n.string("GitHub authorization is required to synchronize this private repository."),
                                systemImage: store.gitHubIsAuthorized ? "checkmark.circle.fill" : "lock.shield"
                            )
                            .font(.caption)
                            .foregroundStyle(store.gitHubIsAuthorized ? .green : .secondary)
                            Spacer()
                            Button {
                                reauthorizeGitHub(project)
                            } label: {
                                Label(
                                    githubAuthorization == nil
                                        ? L10n.string("Reauthorize GitHub")
                                        : L10n.string("Authorizing…"),
                                    systemImage: "arrow.clockwise.icloud"
                                )
                            }
                            .buttonStyle(.bordered)
                            .disabled(
                                !store.gitHubRepositoryCreationIsConfigured
                                    || githubAuthorization != nil
                                    || isWorking
                            )
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.string("Invite a GitHub collaborator"))
                            .font(.headline)
                        Text(L10n.string("They must accept GitHub's invitation before joining this private project."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField(L10n.string("GitHub username"), text: $collaboratorUsername)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { inviteCollaborator(project) }
                            Button(L10n.string("Invite")) {
                                inviteCollaborator(project)
                            }
                            .disabled(
                                collaboratorUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || isWorking
                            )
                        }
                        if collaboratorInvitationSent {
                            Label(
                                L10n.string("GitHub invitation sent. Share the project invitation after it is accepted."),
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.green)
                        }
                    }
                }
                if !store.pendingSyncConflicts.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Label(
                            L10n.string("Choose which version to keep"),
                            systemImage: "arrow.triangle.branch"
                        )
                        .font(.headline)
                        Text(L10n.string("Only items changed in both copies need a decision."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(store.pendingSyncConflicts) { conflict in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(localizedEntityType(conflict.entityType))
                                        .font(.callout.weight(.medium))
                                    Text(conflict.entityID)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button(L10n.string("Keep Mine")) {
                                    conflictChoices[conflict.id] = false
                                }
                                .buttonStyle(.bordered)
                                .tint(conflictChoices[conflict.id] == false ? .accentColor : .secondary)
                                Button(L10n.string("Use Shared")) {
                                    conflictChoices[conflict.id] = true
                                }
                                .buttonStyle(.bordered)
                                .tint(conflictChoices[conflict.id] == true ? .accentColor : .secondary)
                            }
                        }
                        HStack {
                            Spacer()
                            Button(L10n.string("Finish Synchronizing")) {
                                resolve(project)
                            }
                            .buttonStyle(.glassProminent)
                            .disabled(
                                conflictChoices.count != store.pendingSyncConflicts.count || isWorking
                            )
                        }
                    }
                }
                HStack {
                    Button {
                        createInvitation(project)
                    } label: {
                        Label(L10n.string("Copy Invitation"), systemImage: "person.badge.plus")
                    }
                    .disabled(isWorking)

                    if let invitation {
                        ShareLink(item: invitation) {
                            Label(L10n.string("Share Invitation…"), systemImage: "square.and.arrow.up")
                        }
                    }

                    Spacer()

                    Button {
                        synchronize(project)
                    } label: {
                        Label(
                            isWorking ? L10n.string("Synchronizing…") : L10n.string("Synchronize Now"),
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isWorking || githubAuthorization != nil)
                }
                if invitation != nil {
                    Label(L10n.string("Invitation copied. It contains the repository address, never credentials."), systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        } label: {
            Label(L10n.string("Shared"), systemImage: "person.2")
        }
    }

    private var isWorking: Bool {
        store.projectSyncState == .working
    }

    private func connect(_ project: FSProject) {
        errorMessage = nil
        Task {
            switch await store.connectSharedRepository(remoteURL: remoteURL, projectID: project.id) {
            case .success:
                synchronize(project)
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func prepareRepository(_ project: FSProject) {
        errorMessage = nil
        Task {
            if case let .failure(error) = await store.prepareManagedRepository(project.id) {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func createOnGitHub(_ project: FSProject) {
        errorMessage = nil
        createdGitHubRepository = nil
        Task {
            switch await store.beginGitHubRepositoryCreation() {
            case let .success(authorization):
                githubAuthorization = authorization
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(authorization.userCode, forType: .string)
                NSWorkspace.shared.open(authorization.verificationURL)
                switch await store.finishGitHubRepositoryCreation(
                    authorization: authorization,
                    projectID: project.id
                ) {
                case let .success(repository):
                    createdGitHubRepository = repository
                    githubAuthorization = nil
                case let .failure(error):
                    githubAuthorization = nil
                    errorMessage = error.localizedDescription
                }
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func synchronize(_ project: FSProject) {
        errorMessage = nil
        Task {
            if case let .failure(error) = await store.synchronizeProject(project.id) {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reauthorizeGitHub(_ project: FSProject) {
        errorMessage = nil
        Task {
            switch await store.beginGitHubRepositoryCreation() {
            case let .failure(error):
                errorMessage = error.localizedDescription
            case let .success(authorization):
                githubAuthorization = authorization
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(authorization.userCode, forType: .string)
                NSWorkspace.shared.open(authorization.verificationURL)
                switch await store.finishGitHubAuthorization(authorization) {
                case .success:
                    githubAuthorization = nil
                    synchronize(project)
                case let .failure(error):
                    githubAuthorization = nil
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func createInvitation(_ project: FSProject) {
        errorMessage = nil
        Task {
            switch await store.projectInvitation(project.id) {
            case let .success(value):
                invitation = value
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func inviteCollaborator(_ project: FSProject) {
        errorMessage = nil
        collaboratorInvitationSent = false
        Task {
            switch await store.inviteGitHubCollaborator(
                username: collaboratorUsername,
                projectID: project.id
            ) {
            case .success:
                collaboratorInvitationSent = true
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func isGitHubURL(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized.hasPrefix("https://github.com/")
            || normalized.hasPrefix("ssh://git@github.com/")
            || normalized.hasPrefix("git@github.com:")
    }

    private func resolve(_ project: FSProject) {
        errorMessage = nil
        Task {
            if case let .failure(error) = await store.resolveProjectSynchronization(
                project.id,
                choices: conflictChoices
            ) {
                errorMessage = error.localizedDescription
            } else {
                conflictChoices = [:]
            }
        }
    }

    private func localizedEntityType(_ type: String) -> String {
        switch type {
        case "project": L10n.string("Project")
        case "profile": L10n.string("Profile")
        case "story": L10n.string("Story")
        default: type.capitalized
        }
    }
}
