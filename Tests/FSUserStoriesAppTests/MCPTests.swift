// SPDX-License-Identifier: MIT

import Foundation
import XCTest
@testable import FSUserStoriesApp

@MainActor
final class MCPTests: XCTestCase {
    func testBundledGitHubOAuthClientIDIsConfigured() {
        XCTAssertTrue(GitHubService().isConfigured)
    }

    func testInitializeNegotiatesProtocol() throws {
        let store = AppStore.preview
        let response = try XCTUnwrap(
            store.handleMCPRequest(
                MCPRequest(
                    jsonrpc: "2.0",
                    id: .integer(1),
                    method: "initialize",
                    params: .object(["protocolVersion": .string("2025-06-18")])
                )
            )
        )

        XCTAssertNil(response.error)
        XCTAssertEqual(response.result?.objectValue?["protocolVersion"], .string("2025-06-18"))
        XCTAssertNotNil(response.result?.objectValue?["capabilities"]?.objectValue?["prompts"])
    }

    func testMCPAdvertisesRepositorySynchronizationTools() throws {
        let store = AppStore.preview
        let response = try XCTUnwrap(
            store.handleMCPRequest(
                MCPRequest(
                    jsonrpc: "2.0",
                    id: .integer(1),
                    method: "tools/list",
                    params: .object([:])
                )
            )
        )
        let names = try XCTUnwrap(response.result?.objectValue?["tools"]?.arrayValue)
            .compactMap { $0.objectValue?["name"]?.stringValue }
        XCTAssertTrue(names.contains("get_repository_status"))
        XCTAssertTrue(names.contains("connect_shared_repository"))
        XCTAssertTrue(names.contains("synchronize_project"))
        XCTAssertTrue(names.contains("create_share_invitation"))
    }

    func testBundledRustCoreCreatesCredentialFreeInvitation() throws {
        let core = try RustCoreClient()
        let result = try core.execute([
            "command": "create_invitation",
            "project_id": UUID().uuidString,
            "project_name": "Example",
            "remote_url": "git@example.com:team/example.git",
            "default_branch": "main"
        ])
        let invitation = try XCTUnwrap(result["invitation"] as? String)
        XCTAssertFalse(invitation.isEmpty)
        XCTAssertFalse(invitation.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(invitation.localizedCaseInsensitiveContains("password"))
    }

    func testAnalyzeExistingProjectPromptIncludesCurrentProject() throws {
        let store = AppStore.preview
        let project = try XCTUnwrap(store.projects.first)

        let listResponse = try XCTUnwrap(
            store.handleMCPRequest(
                MCPRequest(
                    jsonrpc: "2.0",
                    id: .integer(1),
                    method: "prompts/list",
                    params: .object([:])
                )
            )
        )
        let prompts = try XCTUnwrap(listResponse.result?.objectValue?["prompts"]?.arrayValue)
        XCTAssertEqual(prompts.first?.objectValue?["name"], .string("analyze_existing_project"))

        let getResponse = try XCTUnwrap(
            store.handleMCPRequest(
                MCPRequest(
                    jsonrpc: "2.0",
                    id: .integer(2),
                    method: "prompts/get",
                    params: .object([
                        "name": .string("analyze_existing_project"),
                        "arguments": .object([
                            "project_id": .string(project.id.uuidString),
                            "scope": .string("Authentication")
                        ])
                    ])
                )
            )
        )
        let messages = try XCTUnwrap(getResponse.result?.objectValue?["messages"]?.arrayValue)
        let promptText = try XCTUnwrap(
            messages.first?.objectValue?["content"]?.objectValue?["text"]?.stringValue
        )
        XCTAssertTrue(promptText.contains(project.name))
        XCTAssertTrue(promptText.contains("Authentication"))
        XCTAssertTrue(promptText.contains("Do not create, edit, or delete anything"))
    }

    func testMCPCanCreateAndEditLocalStory() throws {
        let store = AppStore.preview
        let project = try XCTUnwrap(store.projects.first)
        let actor = try XCTUnwrap(project.actors.first)
        let initialCount = project.stories.count

        _ = call(
            "create_story",
            arguments: [
                "project_id": .string(project.id.uuidString),
                "title": .string("Connect an agent"),
                "actor_id": .string(actor.id.uuidString),
                "want": .string("to read local stories"),
                "outcome": .string("implementation follows the requirements"),
                "acceptance_criteria": .array([.string("The client can list stories")])
            ],
            store: store
        )

        let created = try XCTUnwrap(store.projects.first?.stories.last)
        XCTAssertEqual(store.projects.first?.stories.count, initialCount + 1)
        XCTAssertEqual(created.title, "Connect an agent")

        _ = call(
            "update_story",
            arguments: [
                "project_id": .string(project.id.uuidString),
                "story_id": .string(created.id.uuidString),
                "title": .string("Connect any MCP client")
            ],
            store: store
        )

        XCTAssertEqual(store.projects.first?.stories.last?.title, "Connect any MCP client")
    }

    func testCompletedStoriesAreReadOnlyThroughMCP() throws {
        let store = AppStore.preview
        let project = try XCTUnwrap(store.projects.first)
        let story = try XCTUnwrap(project.stories.first)
        for criterion in story.acceptanceCriteria {
            store.setAcceptanceCriterion(
                criterion.id,
                isMet: true,
                in: story.id,
                projectID: project.id
            )
        }
        store.setStoryStatus(.done, for: story.id, projectID: project.id)

        let response = call(
            "update_story",
            arguments: [
                "project_id": .string(project.id.uuidString),
                "story_id": .string(story.id.uuidString),
                "title": .string("This must not be saved")
            ],
            store: store
        )

        XCTAssertEqual(store.projects.first?.stories.first?.title, story.title)
        XCTAssertEqual(response.result?.objectValue?["isError"], .bool(true))
    }

    func testCompletionRuleIsSharedByApplicationAndMCP() throws {
        let store = AppStore.preview
        let project = try XCTUnwrap(store.projects.first)
        let story = try XCTUnwrap(project.stories.first)

        let applicationResult = store.setStoryStatus(.done, for: story.id, projectID: project.id)
        guard case .failure(.incompleteAcceptanceCriteria) = applicationResult else {
            return XCTFail("The application layer must reject incomplete stories")
        }

        let mcpResponse = call(
            "set_story_status",
            arguments: [
                "project_id": .string(project.id.uuidString),
                "story_id": .string(story.id.uuidString),
                "status": .string("done")
            ],
            store: store
        )

        XCTAssertEqual(store.projects.first?.stories.first?.status, .draft)
        XCTAssertEqual(mcpResponse.result?.objectValue?["isError"], .bool(true))
    }

    func testActorCRUDAndDestructiveConfirmation() throws {
        let store = AppStore.preview
        let project = try XCTUnwrap(store.projects.first)
        let initialCount = project.actors.count

        _ = call(
            "create_actor",
            arguments: [
                "project_id": .string(project.id.uuidString),
                "name": .string("QA Engineer"),
                "role": .string("Validates product behavior")
            ],
            store: store
        )
        let actor = try XCTUnwrap(store.projects.first?.actors.last)
        XCTAssertEqual(store.projects.first?.actors.count, initialCount + 1)

        _ = call(
            "update_actor",
            arguments: [
                "project_id": .string(project.id.uuidString),
                "actor_id": .string(actor.id.uuidString),
                "role": .string("Validates acceptance criteria")
            ],
            store: store
        )
        XCTAssertEqual(store.projects.first?.actors.last?.role, "Validates acceptance criteria")

        let refused = call(
            "delete_actor",
            arguments: [
                "project_id": .string(project.id.uuidString),
                "actor_id": .string(actor.id.uuidString)
            ],
            store: store
        )
        XCTAssertEqual(refused.result?.objectValue?["isError"], .bool(true))

        _ = call(
            "delete_actor",
            arguments: [
                "project_id": .string(project.id.uuidString),
                "actor_id": .string(actor.id.uuidString),
                "confirm": .bool(true)
            ],
            store: store
        )
        XCTAssertEqual(store.projects.first?.actors.count, initialCount)
    }

    func testMCPAddsAndResolvesManagedAttachment() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let sourceURL = temporaryRoot.appending(path: "acceptance.txt")
        try Data("Accepted".utf8).write(to: sourceURL)
        let preview = AppStore.preview
        let store = AppStore(
            projects: preview.projects,
            attachmentStorage: try AttachmentStorage(
                rootURL: temporaryRoot.appending(path: "managed", directoryHint: .isDirectory)
            )
        )
        let project = try XCTUnwrap(store.projects.first)
        let story = try XCTUnwrap(project.stories.first)

        _ = call(
            "add_attachments",
            arguments: [
                "project_id": .string(project.id.uuidString),
                "story_id": .string(story.id.uuidString),
                "paths": .array([.string(sourceURL.path)])
            ],
            store: store
        )

        let attachment = try XCTUnwrap(store.projects.first?.stories.first?.attachments.first)
        let resource = try XCTUnwrap(store.mcpAttachmentResource(attachment.id))
        XCTAssertEqual(try Data(contentsOf: resource.url), Data("Accepted".utf8))
    }

    func testHTTPServerAcceptsLoopbackAndRejectsForeignOrigins() async throws {
        let ready = expectation(description: "MCP server is ready")
        let resourceID = UUID()
        let resourceURL = FileManager.default.temporaryDirectory.appending(path: resourceID.uuidString)
        try Data("attachment-body".utf8).write(to: resourceURL)
        defer { try? FileManager.default.removeItem(at: resourceURL) }
        let server = LocalMCPServer(
            port: 49_232,
            handler: { request in
                guard let id = request.id else { return nil }
                return .success(id: id, result: .object([:]))
            },
            resourceHandler: { id in
                guard id == resourceID else { return nil }
                return MCPHTTPResource(
                    url: resourceURL,
                    contentType: "text/plain",
                    filename: "attachment.txt"
                )
            },
            stateChanged: { state in
                if state == .running {
                    ready.fulfill()
                }
            }
        )
        defer { server.stop() }
        try server.start()
        await fulfillment(of: [ready], timeout: 2)

        let payload = Data(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.utf8)
        var request = URLRequest(url: server.endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload

        let (_, acceptedResponse) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((acceptedResponse as? HTTPURLResponse)?.statusCode, 200)

        let attachmentURL = URL(string: "http://127.0.0.1:49232/attachments/\(resourceID.uuidString)")!
        let (attachmentData, attachmentResponse) = try await URLSession.shared.data(from: attachmentURL)
        XCTAssertEqual((attachmentResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(attachmentData, Data("attachment-body".utf8))

        request.setValue("https://example.com", forHTTPHeaderField: "Origin")
        let (_, rejectedResponse) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((rejectedResponse as? HTTPURLResponse)?.statusCode, 403)
    }

    private func call(
        _ name: String,
        arguments: [String: JSONValue],
        store: AppStore
    ) -> MCPResponse {
        store.handleMCPRequest(
            MCPRequest(
                jsonrpc: "2.0",
                id: .integer(1),
                method: "tools/call",
                params: .object([
                    "name": .string(name),
                    "arguments": .object(arguments)
                ])
            )
        )!
    }
}
