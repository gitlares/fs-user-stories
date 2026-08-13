// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    let store: AppStore

    var body: some View {
        if store.projects.isEmpty {
            Text(L10n.string("No projects yet"))
        } else {
            ForEach(store.projects) { project in
                Menu(project.name) {
                    Section(L10n.string("Active Stories")) {
                        let activeStories = project.stories.filter { $0.status == .active }

                        if activeStories.isEmpty {
                            Text(L10n.string("No active stories"))
                        } else {
                            ForEach(activeStories) { story in
                                Button {
                                    open(story: story, in: project)
                                } label: {
                                    Text("\(project.prefix)-\(story.number)  \(story.title)")
                                }
                            }
                        }
                    }

                    Divider()

                    if project.actors.isEmpty {
                        Text(L10n.string("Add an actor before creating a story."))
                    }

                    Button {
                        createStory(in: project)
                    } label: {
                        Label(L10n.string("New Story…"), systemImage: "square.and.pencil")
                    }
                    .disabled(project.actors.isEmpty)
                }
            }
        }

        Divider()

        Section(L10n.string("MCP Server")) {
            Label(mcpStatusTitle, systemImage: mcpStatusSymbol)

            Text(store.mcpServerURL.absoluteString)

            Button {
                copyMCPURL()
            } label: {
                Label(L10n.string("Copy MCP URL"), systemImage: "doc.on.doc")
            }
            .disabled(store.mcpServerState != .running)

            Button {
                showMCPConnection()
            } label: {
                Label(L10n.string("Connection Instructions…"), systemImage: "questionmark.circle")
            }
        }

        Divider()

        Button {
            showWorkspace()
        } label: {
            Label(L10n.string("Show FS User Stories"), systemImage: "macwindow")
        }

        Divider()

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label(L10n.string("Quit FS User Stories"), systemImage: "power")
        }
        .keyboardShortcut("q")
    }

    private func open(story: UserStory, in project: FSProject) {
        store.selectStory(story.id, in: project.id)
        showWorkspace()
    }

    private func createStory(in project: FSProject) {
        store.requestStoryCreation(in: project.id)
        showWorkspace()
    }

    private func showWorkspace() {
        openWindow(id: "workspace")
        NSApplication.shared.activate()
    }

    private var mcpStatusTitle: String {
        switch store.mcpServerState {
        case .stopped:
            L10n.string("Stopped")
        case .starting:
            L10n.string("Starting…")
        case .running:
            L10n.string("Running locally")
        case let .failed(message):
            String(format: L10n.string("MCP server failed: %@"), message)
        }
    }

    private var mcpStatusSymbol: String {
        switch store.mcpServerState {
        case .running: "circle.fill"
        case .starting: "hourglass"
        case .stopped, .failed: "exclamationmark.circle"
        }
    }

    private func copyMCPURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.mcpServerURL.absoluteString, forType: .string)
    }

    private func showMCPConnection() {
        openWindow(id: "mcp-connection")
        NSApplication.shared.activate()
    }
}
