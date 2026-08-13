// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

struct GitJoinView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: AppStore
    @State private var invitation = ""
    @State private var errorMessage: String?
    @State private var githubAuthorization: GitHubDeviceAuthorization?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 16) {
                    Image(systemName: "person.2.badge.plus")
                        .font(.system(size: 40))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.string("Join Shared Project"))
                            .font(.title.bold())
                        Text(L10n.string("Paste the invitation sent by a collaborator."))
                            .foregroundStyle(.secondary)
                    }
                }

                TextEditor(text: $invitation)
                    .font(.body.monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 150)
                    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.separator)
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
                        Text(L10n.string("Waiting for GitHub authorization…"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
                }

                Label(
                    L10n.string("Invitations contain a repository address, not passwords or access tokens."),
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            .padding(30)

            Spacer()
            Divider()
            HStack {
                Button(L10n.string("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.string("Join Project")) { join() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        invitation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || githubAuthorization != nil
                            || store.projectSyncState == .working
                    )
            }
            .padding(20)
        }
        .frame(width: 560)
        .frame(minHeight: 430)
    }

    private func join() {
        errorMessage = nil
        Task {
            switch store.sharedInvitationUsesGitHub(invitation) {
            case let .failure(error):
                errorMessage = error.localizedDescription
                return
            case let .success(usesGitHub):
                if usesGitHub && !store.gitHubIsAuthorized {
                    guard await authorizeGitHub() else { return }
                }
            }
            await finishJoining()
        }
    }

    private func authorizeGitHub() async -> Bool {
        switch await store.beginGitHubRepositoryCreation() {
        case let .failure(error):
            errorMessage = error.localizedDescription
            return false
        case let .success(authorization):
            githubAuthorization = authorization
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(authorization.userCode, forType: .string)
            NSWorkspace.shared.open(authorization.verificationURL)
            switch await store.finishGitHubAuthorization(authorization) {
            case .success:
                githubAuthorization = nil
                return true
            case let .failure(error):
                githubAuthorization = nil
                errorMessage = error.localizedDescription
                return false
            }
        }
    }

    private func finishJoining() async {
        switch await store.joinSharedProject(invitation: invitation) {
            case .success:
                dismiss()
            case let .failure(error):
                errorMessage = error.localizedDescription
        }
    }
}
