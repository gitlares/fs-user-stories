// SPDX-License-Identifier: MIT

import SwiftUI

struct GitJoinView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: AppStore
    @State private var invitation = ""
    @State private var errorMessage: String?

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
                            || store.projectSyncState == .working
                    )
            }
            .padding(20)
        }
        .frame(width: 560, height: 430)
    }

    private func join() {
        errorMessage = nil
        Task {
            switch await store.joinSharedProject(invitation: invitation) {
            case .success:
                dismiss()
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
    }
}
