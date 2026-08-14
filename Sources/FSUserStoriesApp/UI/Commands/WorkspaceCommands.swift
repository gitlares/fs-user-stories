// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

struct WorkspaceCommandActions {
    let canCreateStory: Bool
    let hasSelectedStory: Bool
    let canEditSelectedStory: Bool
    let createProject: () -> Void
    let createStory: () -> Void
    let editStory: () -> Void
    let duplicateStory: () -> Void
    let requestStoryDeletion: () -> Void
}

private struct WorkspaceCommandActionsKey: FocusedValueKey {
    typealias Value = WorkspaceCommandActions
}

extension FocusedValues {
    var workspaceCommandActions: WorkspaceCommandActions? {
        get { self[WorkspaceCommandActionsKey.self] }
        set { self[WorkspaceCommandActionsKey.self] = newValue }
    }
}

struct StoryCommands: Commands {
    @FocusedValue(\.workspaceCommandActions) private var actions
    @Environment(\.openWindow) private var openWindow
    let store: AppStore

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L10n.string("About FS User Stories")) {
                AppReleaseInfo.presentAboutPanel()
            }
        }

        CommandGroup(replacing: .newItem) {
            Button(L10n.string("New Story")) {
                actions?.createStory()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(actions?.canCreateStory != true)

            Button(L10n.string("New Project")) {
                actions?.createProject()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(actions == nil)
        }

        CommandMenu(L10n.string("Story")) {
            Button(L10n.string("Edit Story")) {
                actions?.editStory()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(actions?.canEditSelectedStory != true)

            Button(L10n.string("Duplicate Story")) {
                actions?.duplicateStory()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(actions?.hasSelectedStory != true)

            Divider()

            Button(L10n.string("Delete Story")) {
                actions?.requestStoryDeletion()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(actions?.hasSelectedStory != true)
        }

        CommandMenu(mcpMenuTitle) {
            Label(mcpStatusTitle, systemImage: mcpStatusSymbol)
                .disabled(true)

            Text(store.mcpServerURL.absoluteString)

            Button(L10n.string("Copy MCP URL")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    store.mcpServerURL.absoluteString,
                    forType: .string
                )
            }
            .disabled(store.mcpServerState != .running)

            Divider()

            Button(L10n.string("Connection Instructions…")) {
                openWindow(id: "mcp-connection")
                NSApplication.shared.activate()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
        }
    }

    private var mcpMenuTitle: String {
        store.mcpServerState == .running
            ? L10n.string("MCP — Active")
            : L10n.string("MCP — Inactive")
    }

    private var mcpStatusTitle: String {
        switch store.mcpServerState {
        case .running:
            L10n.string("Running locally")
        case .starting:
            L10n.string("Starting…")
        case .stopped:
            L10n.string("Stopped")
        case let .failed(message):
            String(format: L10n.string("MCP server failed: %@"), message)
        }
    }

    private var mcpStatusSymbol: String {
        switch store.mcpServerState {
        case .running: "checkmark.circle.fill"
        case .starting: "hourglass"
        case .stopped, .failed: "exclamationmark.circle.fill"
        }
    }
}
