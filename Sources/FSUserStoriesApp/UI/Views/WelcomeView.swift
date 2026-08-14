// SPDX-License-Identifier: MIT

import SwiftUI

struct WelcomeView: View {
    let createProject: () -> Void
    let joinWithInvitation: () -> Void
    let connectRepository: () -> Void

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 29, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                }
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text(L10n.string("Start with a project"))
                        .font(.system(size: 28, weight: .semibold))
                    Text(L10n.string("Create a focused space for your actors and user stories."))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    Button(action: createProject) {
                        Label(L10n.string("Create Project"), systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut("n", modifiers: .command)

                    Button(action: joinWithInvitation) {
                        Label(L10n.string("Use an Invitation"), systemImage: "person.2.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)

                    Button(action: connectRepository) {
                        Label(L10n.string("Connect Existing Repository"), systemImage: "externaldrive.connected.to.line.below")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
                .frame(maxWidth: 300)
            }
            .frame(maxWidth: 420)
            .multilineTextAlignment(.center)
            .padding(48)
        }
    }
}
