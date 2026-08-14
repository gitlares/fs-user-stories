// SPDX-License-Identifier: MIT

import Foundation

enum MCPServerState: Equatable, Sendable {
    case stopped
    case starting
    case running
    case failed(String)
}

/// Launches the Rust-owned loopback MCP daemon. Swift deliberately does not
/// parse messages, register tools, or access MCP resources.
final class RustMCPServer: @unchecked Sendable {
    static let defaultPort: UInt16 = 49_231

    let endpointURL: URL
    private let process = Process()
    private let stateChanged: @MainActor @Sendable (MCPServerState) -> Void

    init(
        databaseURL: URL,
        attachmentsRootURL: URL,
        coreExecutableURL: URL,
        port: UInt16 = RustMCPServer.defaultPort,
        stateChanged: @escaping @MainActor @Sendable (MCPServerState) -> Void
    ) {
        endpointURL = URL(string: "http://127.0.0.1:\(port)/mcp")!
        self.stateChanged = stateChanged
        process.executableURL = coreExecutableURL
        process.arguments = [
            "--mcp-server",
            "--database-path", databaseURL.path,
            "--attachments-root", attachmentsRootURL.path,
            "--port", "\(port)"
        ]
    }

    func start() throws {
        let errors = Pipe()
        process.standardError = errors
        process.terminationHandler = { [stateChanged] process in
            let output = String(
                data: errors.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor in
                stateChanged(.failed(output?.isEmpty == false ? output! : "The local Rust MCP server stopped (\(process.terminationStatus))."))
            }
        }
        try process.run()
        Task { @MainActor in stateChanged(.running) }
    }

    func stop() {
        guard process.isRunning else { return }
        process.terminate()
    }
}
