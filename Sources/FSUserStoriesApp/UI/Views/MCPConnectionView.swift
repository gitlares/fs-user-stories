// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

struct MCPConnectionView: View {
    let store: AppStore
    @State private var copiedItem: CopiedItem?

    private enum CopiedItem {
        case url
        case configuration
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                connectionCard
                instructions
                configuration
                privacyNote
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(36)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(L10n.string("MCP Connection"))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 34, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 52, height: 52)
                .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("Connect an AI Client"))
                    .font(.largeTitle.weight(.semibold))

                Text(
                    L10n.string(
                        "Connect any MCP client to your local projects while FS User Stories is running."
                    )
                )
                .font(.title3)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(mcpStatusTitle, systemImage: mcpStatusSymbol)
                    .font(.headline)
                    .foregroundStyle(statusColor)

                Spacer()

                Text(L10n.string("Local only"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }

            connectionRow(label: L10n.string("Transport"), value: "Streamable HTTP")
            connectionRow(label: L10n.string("Host"), value: "127.0.0.1")
            connectionRow(label: L10n.string("Port"), value: "\(LocalMCPServer.defaultPort)")

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("MCP URL"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Text(store.mcpServerURL.absoluteString)
                        .font(.body.monospaced())
                        .textSelection(.enabled)

                    Spacer()

                    Button {
                        copy(store.mcpServerURL.absoluteString, item: .url)
                    } label: {
                        Label(
                            copiedItem == .url ? L10n.string("Copied") : L10n.string("Copy URL"),
                            systemImage: copiedItem == .url ? "checkmark" : "doc.on.doc"
                        )
                    }
                    .buttonStyle(.glass)
                    .disabled(store.mcpServerState != .running)
                }
            }
        }
        .padding(22)
        .background(.background.secondary, in: .rect(cornerRadius: 20))
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("How to Connect"))
                .font(.title2.weight(.semibold))

            instructionRow(
                number: 1,
                title: L10n.string("Open your AI client's MCP settings."),
                detail: L10n.string("Look for MCP Servers, Tools, Integrations, or Developer settings.")
            )
            instructionRow(
                number: 2,
                title: L10n.string("Add a remote or HTTP MCP server."),
                detail: L10n.string("Choose Streamable HTTP when the client asks for a transport.")
            )
            instructionRow(
                number: 3,
                title: L10n.string("Paste the MCP URL shown above."),
                detail: L10n.string("No account, token, command, or external server is required.")
            )
            instructionRow(
                number: 4,
                title: L10n.string("Keep FS User Stories running."),
                detail: L10n.string("Closing the window is fine. Quitting the app stops the MCP server.")
            )
        }
    }

    private var configuration: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string("Example Configuration"))
                        .font(.title3.weight(.semibold))
                    Text(L10n.string("Field names can vary between MCP clients."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    copy(configurationText, item: .configuration)
                } label: {
                    Label(
                        copiedItem == .configuration ? L10n.string("Copied") : L10n.string("Copy Configuration"),
                        systemImage: copiedItem == .configuration ? "checkmark" : "doc.on.doc"
                    )
                }
                .buttonStyle(.glass)
            }

            Text(configurationText)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 12))
        }
    }

    private var privacyNote: some View {
        Label {
            Text(
                L10n.string(
                    "The server listens only on this Mac. Your AI client may still send story content to its configured model provider."
                )
            )
        } icon: {
            Image(systemName: "hand.raised.fill")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(16)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 14))
    }

    private var configurationText: String {
        """
        {
          "mcpServers": {
            "fs-user-stories": {
              "type": "http",
              "url": "\(store.mcpServerURL.absoluteString)"
            }
          }
        }
        """
    }

    private func connectionRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.monospaced())
                .textSelection(.enabled)
        }
    }

    private func instructionRow(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 24, height: 24)
                .foregroundStyle(.white)
                .background(Color.accentColor, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var mcpStatusTitle: String {
        switch store.mcpServerState {
        case .running: L10n.string("MCP Server Running")
        case .starting: L10n.string("Starting MCP Server…")
        case .stopped: L10n.string("MCP Server Stopped")
        case let .failed(message): String(format: L10n.string("MCP server failed: %@"), message)
        }
    }

    private var mcpStatusSymbol: String {
        switch store.mcpServerState {
        case .running: "checkmark.circle.fill"
        case .starting: "hourglass"
        case .stopped, .failed: "exclamationmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch store.mcpServerState {
        case .running: .green
        case .starting: .secondary
        case .stopped, .failed: .red
        }
    }

    private func copy(_ value: String, item: CopiedItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copiedItem = item
    }
}
