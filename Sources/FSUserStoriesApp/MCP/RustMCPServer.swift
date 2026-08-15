// SPDX-License-Identifier: MIT

import Foundation
import Darwin

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
    private let mayRecoverPreviousOwnedServer: Bool

    init(
        databaseURL: URL,
        attachmentsRootURL: URL,
        coreExecutableURL: URL,
        port: UInt16 = RustMCPServer.defaultPort,
        mayRecoverPreviousOwnedServer: Bool = !AppDistribution.isMacAppStore,
        stateChanged: @escaping @MainActor @Sendable (MCPServerState) -> Void
    ) {
        endpointURL = URL(string: "http://127.0.0.1:\(port)/mcp")!
        self.stateChanged = stateChanged
        self.mayRecoverPreviousOwnedServer = mayRecoverPreviousOwnedServer
        process.executableURL = coreExecutableURL
        process.arguments = [
            "--mcp-server",
            "--database-path", databaseURL.path,
            "--attachments-root", attachmentsRootURL.path,
            "--port", "\(port)"
        ]
    }

    func start() throws {
        // The direct build can recover a stale process left by an older app
        // instance. App Sandbox intentionally forbids inspecting or ending
        // unrelated processes, so the Store build relies on its own lifecycle
        // delegate to stop the embedded core when the app quits.
        if mayRecoverPreviousOwnedServer {
            Self.terminatePreviousOwnedServer(on: Self.defaultPort)
        }
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

    private static func terminatePreviousOwnedServer(on port: UInt16) {
        let lsof = Process()
        let output = Pipe()
        lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsof.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"]
        lsof.standardOutput = output
        lsof.standardError = FileHandle.nullDevice
        guard (try? lsof.run()) != nil else { return }
        lsof.waitUntilExit()
        let identifiers = String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.split(whereSeparator: \.isNewline).compactMap { pid_t($0) } ?? []
        for identifier in identifiers where identifier != getpid() {
            var pathBuffer = [CChar](repeating: 0, count: 4_096)
            let length = proc_pidpath(identifier, &pathBuffer, UInt32(pathBuffer.count))
            guard length > 0 else { continue }
            let executablePath = String(
                decoding: pathBuffer.prefix(Int(length)).map { UInt8(bitPattern: $0) },
                as: UTF8.self
            )
            guard isOwnedMCPExecutable(executablePath) else { continue }
            _ = Darwin.kill(identifier, SIGTERM)
        }
    }

    static func isOwnedMCPExecutable(_ path: String) -> Bool {
        path.hasSuffix("/fs-user-stories-core")
            && (
                path.contains("/FS User Stories.app/Contents/Resources/")
                    || path.contains("/FSUserStories_FSUserStoriesApp.bundle/")
            )
    }
}
