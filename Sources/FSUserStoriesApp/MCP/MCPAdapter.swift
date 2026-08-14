// SPDX-License-Identifier: MIT

import Foundation

@MainActor
extension AppStore {
    func handleMCPRequest(_ request: MCPRequest) -> MCPResponse? {
        guard let id = request.id else {
            return nil
        }

        switch request.method {
        case "initialize":
            let requestedVersion = request.params?.objectValue?["protocolVersion"]?.stringValue
            let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
            let protocolVersion = requestedVersion.flatMap {
                supportedVersions.contains($0) ? $0 : nil
            } ?? supportedVersions[0]
            return .success(
                id: id,
                result: .object([
                    "protocolVersion": .string(protocolVersion),
                    "capabilities": .object([
                        "tools": .object(["listChanged": .bool(false)]),
                        "prompts": .object(["listChanged": .bool(false)])
                    ]),
                    "serverInfo": .object([
                        "name": .string("FS User Stories"),
                        "version": .string("0.1.0-alpha.4")
                    ]),
                    "instructions": .string(
                        "FS User Stories is a local-first macOS application for organizing projects, actors, user stories, acceptance criteria, notes, and attachments. Use its tools to inspect work, find open stories, and keep requirements current. Completed stories are read-only until reopened. Destructive tools require confirm=true."
                    )
                ])
            )
        case "ping":
            return .success(id: id, result: .object([:]))
        case "tools/list":
            return .success(id: id, result: .object(["tools": .array(Self.mcpTools)]))
        case "tools/call":
            return handleMCPToolCall(id: id, params: request.params)
        case "prompts/list":
            return .success(id: id, result: .object(["prompts": .array(Self.mcpPrompts)]))
        case "prompts/get":
            return handleMCPPromptGet(id: id, params: request.params)
        default:
            return .failure(id: id, code: -32601, message: "Method not found")
        }
    }

    private func handleMCPPromptGet(id: JSONValue, params: JSONValue?) -> MCPResponse {
        guard
            let params = params?.objectValue,
            params["name"]?.stringValue == "analyze_existing_project",
            let arguments = params["arguments"]?.objectValue,
            let projectID = arguments["project_id"]?.stringValue.flatMap(UUID.init(uuidString:)),
            let project = projects.first(where: { $0.id == projectID })
        else {
            return .failure(id: id, code: -32602, message: "A valid project_id is required")
        }

        let scope = arguments["scope"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let existingActors = project.actors.map { "- \($0.name): \($0.role)" }.joined(separator: "\n")
        let existingStories = project.stories.map {
            "- \(project.prefix)-\($0.number) [\($0.status.rawValue)] \($0.title)"
        }.joined(separator: "\n")
        let scopeInstruction = scope.flatMap { $0.isEmpty ? nil : $0 }
            .map { "Focus the review on: \($0)" }
            ?? "Review the complete codebase available in your current workspace."

        let prompt = """
        Analyze an existing software project and help align it with FS User Stories.

        Project: \(project.name)
        Project ID: \(project.id.uuidString)
        Story prefix: \(project.prefix)
        \(scopeInstruction)

        Existing actors:
        \(existingActors.isEmpty ? "- None" : existingActors)

        Existing stories:
        \(existingStories.isEmpty ? "- None" : existingStories)

        Instructions:
        1. Inspect the actual code, routes, screens, commands, data models, tests, and documentation available to you. Do not infer features without evidence.
        2. Identify only real human or system actors that interact with the product. Keep actor names and roles simple.
        3. Derive user stories from observable behavior using a concise title, actor, "I want", "So that", and verifiable acceptance criteria.
        4. Compare findings with the existing actors and stories above. Avoid duplicates and identify gaps or outdated stories.
        5. Present evidence for every proposed actor or story using relevant file paths or code symbols.
        6. First return a review grouped into: Existing coverage, Missing actors, Missing stories, and Suggested updates.
        7. Do not create, edit, or delete anything until the user explicitly approves the proposal.
        8. After approval, use the FS User Stories MCP tools to apply only the approved changes. Destructive operations still require confirm=true.
        """

        return .success(
            id: id,
            result: .object([
                "description": .string(
                    "Review an existing codebase and propose evidence-based actors and user stories."
                ),
                "messages": .array([
                    .object([
                        "role": .string("user"),
                        "content": .object([
                            "type": .string("text"),
                            "text": .string(prompt)
                        ])
                    ])
                ])
            ])
        )
    }

    private func handleMCPToolCall(id: JSONValue, params: JSONValue?) -> MCPResponse {
        guard
            let params = params?.objectValue,
            let name = params["name"]?.stringValue
        else {
            return .failure(id: id, code: -32602, message: "Invalid tool parameters")
        }
        let arguments = params["arguments"]?.objectValue ?? [:]

        let result: JSONValue
        switch name {
        case "about_app":
            result = aboutApp()
        case "list_projects":
            result = .object(["projects": .array(projects.map(mcpProject))])
        case "create_project":
            result = createProjectFromMCP(arguments)
        case "get_project":
            result = getProject(arguments)
        case "get_repository_status":
            result = getRepositoryStatus(arguments)
        case "connect_shared_repository":
            result = connectSharedRepositoryFromMCP(arguments)
        case "synchronize_project":
            result = synchronizeProjectFromMCP(arguments)
        case "create_share_invitation":
            result = createShareInvitation(arguments)
        case "list_actors":
            result = listActors(arguments)
        case "create_actor":
            result = createActor(arguments)
        case "update_actor":
            result = updateActorFromMCP(arguments)
        case "delete_actor":
            result = deleteActorFromMCP(arguments)
        case "list_stories":
            result = listStories(arguments)
        case "get_story":
            result = getStory(arguments)
        case "create_story":
            result = createStory(arguments)
        case "update_story":
            result = updateStoryFromMCP(arguments)
        case "duplicate_story":
            result = duplicateStoryFromMCP(arguments)
        case "delete_story":
            result = deleteStoryFromMCP(arguments)
        case "add_acceptance_criterion":
            result = addCriterionFromMCP(arguments)
        case "set_acceptance_criterion":
            result = setCriterionFromMCP(arguments)
        case "delete_acceptance_criterion":
            result = deleteCriterionFromMCP(arguments)
        case "set_story_status":
            result = setStatusFromMCP(arguments)
        case "update_notes":
            result = updateNotesFromMCP(arguments)
        case "list_attachments":
            result = listAttachments(arguments)
        case "add_attachments":
            result = addAttachmentsFromMCP(arguments)
        case "get_attachment":
            result = getAttachment(arguments)
        case "delete_attachment":
            result = deleteAttachmentFromMCP(arguments)
        default:
            return .success(id: id, result: mcpToolError("Unknown tool: \(name)"))
        }

        if case let .object(object) = result, object["_error"] != nil {
            return .success(
                id: id,
                result: mcpToolResult(
                    .object(object.filter { $0.key != "_error" }),
                    isError: true
                )
            )
        }
        return .success(id: id, result: mcpToolResult(result, isError: false))
    }

    private func listStories(_ arguments: [String: JSONValue]) -> JSONValue {
        let projectID = arguments["project_id"]?.stringValue.flatMap(UUID.init(uuidString:))
        let actorID = arguments["actor_id"]?.stringValue.flatMap(UUID.init(uuidString:))
        let status = arguments["status"]?.stringValue.flatMap(StoryStatus.init(rawValue:))
        let query = arguments["query"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let createdAfter = dateArgument("created_after", in: arguments)
        let createdBefore = dateArgument("created_before", in: arguments, endOfDay: true)
        let hasOpenCriteria = arguments["has_open_criteria"]?.boolValue

        if arguments["project_id"] != nil, projectID == nil {
            return mcpError("project_id must be a valid UUID")
        }
        if let rawStatus = arguments["status"]?.stringValue, status == nil {
            return mcpError("Unknown status: \(rawStatus)")
        }
        if arguments["created_after"] != nil, createdAfter == nil {
            return mcpError("created_after must be an ISO 8601 date-time")
        }
        if arguments["created_before"] != nil, createdBefore == nil {
            return mcpError("created_before must be an ISO 8601 date-time")
        }

        let stories = stories(matching: StoryQuery(
            projectID: projectID,
            actorID: actorID,
            status: status,
            text: query,
            createdAfter: createdAfter,
            createdBefore: createdBefore,
            hasOpenCriteria: hasOpenCriteria
        )).map { mcpStorySummary($0.story, project: $0.project) }
        return .object(["stories": .array(stories)])
    }

    private func aboutApp() -> JSONValue {
        .object([
            "name": .string("FS User Stories"),
            "version": .string("0.1.0-alpha.4"),
            "description": .string(
                "A local-first macOS workspace for projects, actors, user stories, acceptance criteria, notes, and attachments. The MCP server exposes the same local SQLite-backed domain while the app is running."
            ),
            "source_of_truth": .string("Local SQLite database"),
            "mcp_url": .string(mcpServerURL.absoluteString),
            "destructive_tools_require_confirmation": .bool(true)
        ])
    }

    private func getProject(_ arguments: [String: JSONValue]) -> JSONValue {
        guard
            let projectID = uuidArgument("project_id", in: arguments),
            let project = projects.first(where: { $0.id == projectID })
        else { return mcpError("Project not found") }
        return .object([
            "project": mcpProject(project),
            "stories": .array(project.stories.map { mcpStorySummary($0, project: project) })
        ])
    }

    private func getRepositoryStatus(_ arguments: [String: JSONValue]) -> JSONValue {
        guard let projectID = uuidArgument("project_id", in: arguments),
              let project = projects.first(where: { $0.id == projectID }) else {
            return mcpError("Project not found")
        }
        return mcpRepository(project)
    }

    private func connectSharedRepositoryFromMCP(_ arguments: [String: JSONValue]) -> JSONValue {
        guard let projectID = uuidArgument("project_id", in: arguments),
              let remoteURL = requiredString("remote_url", in: arguments) else {
            return mcpError("project_id and remote_url are required")
        }
        return applicationResult(
            connectSharedRepositoryFromMCP(remoteURL: remoteURL, projectID: projectID),
            transform: mcpProject
        )
    }

    private func synchronizeProjectFromMCP(_ arguments: [String: JSONValue]) -> JSONValue {
        guard confirmed(arguments) else {
            return confirmationError("Synchronizing may publish local project changes to the shared repository.")
        }
        guard let projectID = uuidArgument("project_id", in: arguments) else {
            return mcpError("project_id is required")
        }
        return applicationResult(
            queueProjectSynchronizationFromMCP(projectID),
            transform: { project in
                .object([
                    "project": mcpProject(project),
                    "synchronization": .string("scheduled")
                ])
            }
        )
    }

    private func createShareInvitation(_ arguments: [String: JSONValue]) -> JSONValue {
        guard let projectID = uuidArgument("project_id", in: arguments) else {
            return mcpError("project_id is required")
        }
        return applicationResult(
            projectInvitationFromMCP(projectID),
            transform: { .object(["invitation": .string($0)]) }
        )
    }

    private func createProjectFromMCP(_ arguments: [String: JSONValue]) -> JSONValue {
        guard
            let name = requiredString("name", in: arguments),
            let prefix = requiredString("prefix", in: arguments)
        else { return mcpError("name and prefix are required") }
        return applicationResult(createProject(name: name, prefix: prefix), transform: mcpProject)
    }

    private func listActors(_ arguments: [String: JSONValue]) -> JSONValue {
        guard
            let projectID = uuidArgument("project_id", in: arguments),
            let project = projects.first(where: { $0.id == projectID })
        else { return mcpError("Project not found") }
        return .object(["actors": .array(project.actors.map { mcpActor($0, project: project) })])
    }

    private func createActor(_ arguments: [String: JSONValue]) -> JSONValue {
        guard let projectID = uuidArgument("project_id", in: arguments),
              let name = arguments["name"]?.stringValue else {
            return mcpError("project_id and name are required")
        }
        return applicationResult(
            addActor(name: name, role: arguments["role"]?.stringValue ?? "", to: projectID)
        ) { [self] actor in
            guard let project = projects.first(where: { $0.id == projectID }) else {
                return mcpError(WorkspaceError.projectNotFound.localizedDescription)
            }
            return mcpActor(actor, project: project)
        }
    }

    private func updateActorFromMCP(_ arguments: [String: JSONValue]) -> JSONValue {
        guard
            let projectID = uuidArgument("project_id", in: arguments),
            let actorID = uuidArgument("actor_id", in: arguments),
            let project = projects.first(where: { $0.id == projectID }),
            let actor = project.actors.first(where: { $0.id == actorID })
        else { return mcpError("Project or actor not found") }
        let result = updateActor(
            actorID,
            name: arguments["name"]?.stringValue ?? actor.name,
            role: arguments["role"]?.stringValue ?? actor.role,
            projectID: projectID
        )
        return applicationResult(result) { [self] updatedActor in
            guard let updatedProject = projects.first(where: { $0.id == projectID }) else {
                return mcpError(WorkspaceError.projectNotFound.localizedDescription)
            }
            return mcpActor(updatedActor, project: updatedProject)
        }
    }

    private func deleteActorFromMCP(_ arguments: [String: JSONValue]) -> JSONValue {
        guard confirmed(arguments) else { return confirmationError("delete_actor") }
        guard let projectID = uuidArgument("project_id", in: arguments),
              let actorID = uuidArgument("actor_id", in: arguments) else {
            return mcpError("project_id and actor_id must be valid UUIDs")
        }
        return applicationResult(deleteActor(actorID, projectID: projectID)) { _ in
            .object(["deleted": .bool(true), "actor_id": .string(actorID.uuidString)])
        }
    }

    private func getStory(_ arguments: [String: JSONValue]) -> JSONValue {
        guard let located = locateStory(arguments) else {
            return mcpError("Project or story not found")
        }
        return mcpStory(located.story, project: located.project)
    }

    private func createStory(_ arguments: [String: JSONValue]) -> JSONValue {
        guard let projectID = uuidArgument("project_id", in: arguments),
              let title = arguments["title"]?.stringValue,
              let actorID = uuidArgument("actor_id", in: arguments),
              let want = arguments["want"]?.stringValue,
              let outcome = arguments["outcome"]?.stringValue,
              let criterionValues = arguments["acceptance_criteria"]?.arrayValue else {
            return mcpError(
                "project_id, title, actor_id, want, outcome, and acceptance_criteria are required"
            )
        }

        let criteria = criterionValues.compactMap { value -> AcceptanceCriterion? in
            guard let text = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return AcceptanceCriterion(text: text)
        }
        let result = addStory(
            title: title,
            actorID: actorID,
            want: want,
            outcome: outcome,
            acceptanceCriteria: criteria,
            to: projectID
        )
        return applicationResult(result) { [self] story in
            guard let project = projects.first(where: { $0.id == projectID }) else {
                return mcpError(WorkspaceError.projectNotFound.localizedDescription)
            }
            return mcpStory(story, project: project)
        }
    }

    private func updateStoryFromMCP(_ arguments: [String: JSONValue]) -> JSONValue {
        guard let located = locateStory(arguments) else {
            return mcpError("Project or story not found")
        }
        let title = arguments["title"]?.stringValue ?? located.story.title
        let actorID = arguments["actor_id"]?.stringValue.flatMap(UUID.init(uuidString:))
            ?? located.story.actorID
        let want = arguments["want"]?.stringValue ?? located.story.want
        let outcome = arguments["outcome"]?.stringValue ?? located.story.outcome
        let result = updateStory(
            located.story.id,
            title: title,
            actorID: actorID,
            want: want,
            outcome: outcome,
            acceptanceCriteria: located.story.acceptanceCriteria,
            projectID: located.project.id
        )
        return applicationResult(result) { [self] story in
            guard let project = projects.first(where: { $0.id == located.project.id }) else {
                return mcpError(WorkspaceError.projectNotFound.localizedDescription)
            }
            return mcpStory(story, project: project)
        }
    }

    private func duplicateStoryFromMCP(_ arguments: [String: JSONValue]) -> JSONValue {
        guard let located = locateStory(arguments) else {
            return mcpError("Project or story not found")
        }
        return applicationResult(
            duplicateStory(located.story.id, projectID: located.project.id)
        ) { [self] duplicated in
            guard let project = projects.first(where: { $0.id == located.project.id }) else {
                return mcpError(WorkspaceError.projectNotFound.localizedDescription)
            }
            return mcpStory(duplicated, project: project)
        }
    }

    private func deleteStoryFromMCP(_ arguments: [String: JSONValue]) -> JSONValue {
        guard confirmed(arguments) else { return confirmationError("delete_story") }
        guard let located = locateStory(arguments) else {
            return mcpError("Project or story not found")
        }
        return applicationResult(
            deleteStory(located.story.id, projectID: located.project.id)
        ) { _ in
            .object([
                "deleted": .bool(true),
                "story_id": .string(located.story.id.uuidString),
                "reference": .string("\(located.project.prefix)-\(located.story.number)")
            ])
        }
    }

    private func addCriterionFromMCP(_ arguments: [String: JSONValue]) -> JSONValue {
        guard let located = locateStory(arguments), let text = requiredString("text", in: arguments) else {
            return mcpError("Project, story, or criterion text is invalid")
        }
        return storyResult(
            addAcceptanceCriterion(text: text, to: located.story.id, projectID: located.project.id),
            projectID: located.project.id
        )
    }

    private func setCriterionFromMCP(_ arguments: [String: JSONValue]) -> JSONValue {
        guard
            let located = locateStory(arguments),
            let criterionID = uuidArgument("criterion_id", in: arguments),
            let isMet = arguments["is_met"]?.boolValue
        else {
            return mcpError("Project, story, criterion, or is_met is invalid")
        }
        return storyResult(
            setAcceptanceCriterion(
                criterionID,
                isMet: isMet,
                in: located.story.id,
                projectID: located.project.id
            ),
            projectID: located.project.id
        )
    }

    private func deleteCriterionFromMCP(_ arguments: [String: JSONValue]) -> JSONValue {
        guard confirmed(arguments) else {
            return confirmationError("delete_acceptance_criterion")
        }
        guard let located = locateStory(arguments),
              let criterionID = uuidArgument("criterion_id", in: arguments) else {
            return mcpError("Project, story, or criterion not found")
        }
        return storyResult(
            deleteAcceptanceCriterion(
                criterionID,
                from: located.story.id,
                projectID: located.project.id
            ),
            projectID: located.project.id
        )
    }

    private func setStatusFromMCP(_ arguments: [String: JSONValue]) -> JSONValue {
        guard
            let located = locateStory(arguments),
            let rawStatus = arguments["status"]?.stringValue,
            let status = StoryStatus(rawValue: rawStatus)
        else {
            return mcpError("Project, story, or status is invalid. Use draft, active, or done.")
        }
        return storyResult(
            setStoryStatus(status, for: located.story.id, projectID: located.project.id),
            projectID: located.project.id
        )
    }

    private func updateNotesFromMCP(_ arguments: [String: JSONValue]) -> JSONValue {
        guard let located = locateStory(arguments), let notes = arguments["notes"]?.stringValue else {
            return mcpError("Project, story, or notes is invalid")
        }
        return storyResult(
            updateStoryNotes(notes, for: located.story.id, projectID: located.project.id),
            projectID: located.project.id
        )
    }

    private func listAttachments(_ arguments: [String: JSONValue]) -> JSONValue {
        guard let located = locateStory(arguments) else {
            return mcpError("Project or story not found")
        }
        return .object([
            "attachments": .array(located.story.attachments.map(mcpAttachment))
        ])
    }

    private func addAttachmentsFromMCP(_ arguments: [String: JSONValue]) -> JSONValue {
        guard let located = locateStory(arguments),
              let paths = arguments["paths"]?.arrayValue?.compactMap(\.stringValue),
              !paths.isEmpty else {
            return mcpError("project_id, story_id, and at least one local file path are required")
        }
        let urls = paths.map { URL(filePath: $0) }
        return storyResult(
            importAttachments(from: urls, to: located.story.id, projectID: located.project.id),
            projectID: located.project.id
        )
    }

    private func getAttachment(_ arguments: [String: JSONValue]) -> JSONValue {
        guard
            let located = locateStory(arguments),
            let attachmentID = uuidArgument("attachment_id", in: arguments),
            let attachment = located.story.attachments.first(where: { $0.id == attachmentID })
        else { return mcpError("Project, story, or attachment not found") }
        return mcpAttachment(attachment)
    }

    private func deleteAttachmentFromMCP(_ arguments: [String: JSONValue]) -> JSONValue {
        guard confirmed(arguments) else { return confirmationError("delete_attachment") }
        guard let located = locateStory(arguments),
              let attachmentID = uuidArgument("attachment_id", in: arguments) else {
            return mcpError("Project, story, or attachment not found")
        }
        return applicationResult(
            removeAttachment(attachmentID, from: located.story.id, projectID: located.project.id)
        ) { _ in
            .object(["deleted": .bool(true), "attachment_id": .string(attachmentID.uuidString)])
        }
    }

    func mcpAttachmentResource(_ attachmentID: UUID) -> MCPHTTPResource? {
        for project in projects {
            for story in project.stories {
                guard let attachment = story.attachments.first(where: { $0.id == attachmentID }),
                      let url = attachmentURL(for: attachment) else { continue }
                return MCPHTTPResource(
                    url: url,
                    contentType: attachment.contentType,
                    filename: attachment.filename
                )
            }
        }
        return nil
    }

    private func locateStory(
        _ arguments: [String: JSONValue]
    ) -> (project: FSProject, story: UserStory)? {
        guard
            let projectID = uuidArgument("project_id", in: arguments),
            let storyID = uuidArgument("story_id", in: arguments),
            let project = projects.first(where: { $0.id == projectID }),
            let story = project.stories.first(where: { $0.id == storyID })
        else { return nil }
        return (project, story)
    }

    private func currentMCPStory(projectID: UUID, storyID: UUID) -> JSONValue {
        guard
            let project = projects.first(where: { $0.id == projectID }),
            let story = project.stories.first(where: { $0.id == storyID })
        else { return mcpError("The updated story could not be loaded") }
        return mcpStory(story, project: project)
    }

    private func applicationResult<Value>(
        _ result: Result<Value, WorkspaceError>,
        transform: (Value) -> JSONValue
    ) -> JSONValue {
        switch result {
        case let .success(value):
            transform(value)
        case let .failure(error):
            mcpError(error.localizedDescription)
        }
    }

    private func storyResult(
        _ result: Result<UserStory, WorkspaceError>,
        projectID: UUID
    ) -> JSONValue {
        applicationResult(result) { [self] story in
            guard let project = projects.first(where: { $0.id == projectID }) else {
                return mcpError(WorkspaceError.projectNotFound.localizedDescription)
            }
            return mcpStory(story, project: project)
        }
    }

    private func uuidArgument(_ name: String, in arguments: [String: JSONValue]) -> UUID? {
        arguments[name]?.stringValue.flatMap(UUID.init(uuidString:))
    }

    private func requiredString(_ name: String, in arguments: [String: JSONValue]) -> String? {
        guard let value = arguments[name]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private func dateArgument(
        _ name: String,
        in arguments: [String: JSONValue],
        endOfDay: Bool = false
    ) -> Date? {
        guard let value = arguments[name]?.stringValue else { return nil }
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value) else { return nil }
        if endOfDay {
            return Calendar(identifier: .gregorian)
                .date(byAdding: .day, value: 1, to: date)?
                .addingTimeInterval(-0.001)
        }
        return date
    }

    private func confirmed(_ arguments: [String: JSONValue]) -> Bool {
        arguments["confirm"]?.boolValue == true
    }

    private func confirmationError(_ tool: String) -> JSONValue {
        mcpError("\(tool) is destructive. Call it again with confirm=true after user approval.")
    }

    private func mcpProject(_ project: FSProject) -> JSONValue {
        let activeCount = project.stories.count { $0.status == .active }
        let draftCount = project.stories.count { $0.status == .draft }
        let completedCount = project.stories.count { $0.status == .done }
        return .object([
            "id": .string(project.id.uuidString),
            "name": .string(project.name),
            "prefix": .string(project.prefix),
            "description": .string(
                "\(project.name) contains \(project.stories.count) stories across \(project.actors.count) actors."
            ),
            "actors": .array(project.actors.map { mcpActor($0, project: project) }),
            "story_count": .integer(project.stories.count),
            "active_story_count": .integer(activeCount),
            "draft_story_count": .integer(draftCount),
            "completed_story_count": .integer(completedCount),
            "open_story_count": .integer(activeCount + draftCount),
            "has_open_stories": .bool(activeCount + draftCount > 0),
            "repository": mcpRepository(project)
        ])
    }

    private func mcpRepository(_ project: FSProject) -> JSONValue {
        guard let repository = project.gitRepository else {
            return .object([
                "local_ready": .bool(false),
                "shared": .bool(false)
            ])
        }
        return .object([
            "local_ready": .bool(true),
            "shared": .bool(repository.remoteURL != nil),
            "remote_url": repository.remoteURL.map(JSONValue.string) ?? .null,
            "default_branch": .string(repository.defaultBranch),
            "last_synced_at": repository.lastSyncedAt.map {
                .string($0.formatted(.iso8601))
            } ?? .null,
            "has_pending_conflicts": .bool(!pendingSyncConflicts.isEmpty)
        ])
    }

    private func mcpActor(_ actor: ProjectActor, project: FSProject) -> JSONValue {
        let storyCount = project.stories.count { $0.actorID == actor.id }
        let openStoryCount = project.stories.count {
            $0.actorID == actor.id && $0.status != .done
        }
        return .object([
            "id": .string(actor.id.uuidString),
            "name": .string(actor.name),
            "role": .string(actor.role),
            "story_count": .integer(storyCount),
            "open_story_count": .integer(openStoryCount)
        ])
    }

    private func mcpStorySummary(_ story: UserStory, project: FSProject) -> JSONValue {
        .object([
            "id": .string(story.id.uuidString),
            "project_id": .string(project.id.uuidString),
            "reference": .string("\(project.prefix)-\(story.number)"),
            "title": .string(story.title),
            "actor_id": .string(story.actorID.uuidString),
            "status": .string(story.status.rawValue),
            "criteria_met": .integer(story.metCriteriaCount),
            "criteria_total": .integer(story.acceptanceCriteria.count),
            "has_open_criteria": .bool(story.acceptanceCriteria.contains { !$0.isMet }),
            "created_at": .string(ISO8601DateFormatter().string(from: story.createdAt))
        ])
    }

    private func mcpStory(_ story: UserStory, project: FSProject) -> JSONValue {
        let actor = project.actors.first { $0.id == story.actorID }
        return .object([
            "id": .string(story.id.uuidString),
            "project_id": .string(project.id.uuidString),
            "reference": .string("\(project.prefix)-\(story.number)"),
            "title": .string(story.title),
            "actor": .object([
                "id": .string(story.actorID.uuidString),
                "name": .string(actor?.name ?? ""),
                "role": .string(actor?.role ?? "")
            ]),
            "want": .string(story.want),
            "outcome": .string(story.outcome),
            "notes": .string(story.notes),
            "status": .string(story.status.rawValue),
            "acceptance_criteria": .array(story.acceptanceCriteria.map { criterion in
                .object([
                    "id": .string(criterion.id.uuidString),
                    "text": .string(criterion.text),
                    "is_met": .bool(criterion.isMet)
                ])
            }),
            "completion_percentage": .integer(Int((story.criteriaProgress * 100).rounded())),
            "attachments": .array(story.attachments.map(mcpAttachment)),
            "created_at": .string(ISO8601DateFormatter().string(from: story.createdAt))
        ])
    }

    private func mcpAttachment(_ attachment: StoryAttachment) -> JSONValue {
        let resourceURL = mcpServerURL
            .deletingLastPathComponent()
            .appending(path: "attachments")
            .appending(path: attachment.id.uuidString)
        return .object([
            "id": .string(attachment.id.uuidString),
            "filename": .string(attachment.filename),
            "content_type": .string(attachment.contentType),
            "byte_size": .number(Double(attachment.byteSize)),
            "sha256": .string(attachment.sha256),
            "created_at": .string(ISO8601DateFormatter().string(from: attachment.createdAt)),
            "local_url": .string(resourceURL.absoluteString),
            "available_while_app_is_running": .bool(true)
        ])
    }

    private func mcpError(_ message: String) -> JSONValue {
        .object(["_error": .bool(true), "message": .string(message)])
    }

    private func mcpToolError(_ message: String) -> JSONValue {
        mcpToolResult(.object(["message": .string(message)]), isError: true)
    }

    private func mcpToolResult(_ value: JSONValue, isError: Bool) -> JSONValue {
        let data = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        return .object([
            "content": .array([
                .object(["type": .string("text"), "text": .string(text)])
            ]),
            "structuredContent": value,
            "isError": .bool(isError)
        ])
    }
}

private extension AppStore {
    static var mcpPrompts: [JSONValue] {
        [
            .object([
                "name": .string("analyze_existing_project"),
                "title": .string("Analyze Existing Project"),
                "description": .string(
                    "Inspect the current codebase, compare it with an FS User Stories project, and propose evidence-based actors and stories."
                ),
                "arguments": .array([
                    .object([
                        "name": .string("project_id"),
                        "description": .string("FS User Stories project UUID"),
                        "required": .bool(true)
                    ]),
                    .object([
                        "name": .string("scope"),
                        "description": .string("Optional feature, folder, or product area to review"),
                        "required": .bool(false)
                    ])
                ])
            ])
        ]
    }

    static var mcpTools: [JSONValue] {
        [
            tool("about_app", "Describe FS User Stories, its purpose, storage, and MCP behavior.", properties: [:]),
            tool("list_projects", "List projects with actors, story counts, and open-work summaries.", properties: [:]),
            tool(
                "create_project",
                "Create a local project.",
                properties: [
                    "name": stringProperty("Project name"),
                    "prefix": stringProperty("Short story reference prefix")
                ],
                required: ["name", "prefix"]
            ),
            tool(
                "get_project",
                "Get a project overview, actors, and story summaries.",
                properties: ["project_id": stringProperty("Project UUID")],
                required: ["project_id"]
            ),
            tool(
                "get_repository_status",
                "Get local repository, sharing, last synchronization, and conflict status for a project.",
                properties: ["project_id": stringProperty("Project UUID")],
                required: ["project_id"]
            ),
            tool(
                "connect_shared_repository",
                "Connect a project's managed local repository to an SSH or HTTPS remote.",
                properties: [
                    "project_id": stringProperty("Project UUID"),
                    "remote_url": stringProperty("SSH or HTTPS repository URL")
                ],
                required: ["project_id", "remote_url"]
            ),
            tool(
                "synchronize_project",
                "Queue a background two-way synchronization. It fetches shared changes, merges by project entity, and publishes local changes. Requires explicit confirmation.",
                properties: [
                    "project_id": stringProperty("Project UUID")
                ].merging(confirmProperty) { _, new in new },
                required: ["project_id", "confirm"]
            ),
            tool(
                "create_share_invitation",
                "Create a credential-free invitation for a connected project.",
                properties: ["project_id": stringProperty("Project UUID")],
                required: ["project_id"]
            ),
            tool(
                "list_actors",
                "List actors in a project and their open story counts.",
                properties: ["project_id": stringProperty("Project UUID")],
                required: ["project_id"]
            ),
            tool(
                "create_actor",
                "Create an actor in a project.",
                properties: [
                    "project_id": stringProperty("Project UUID"),
                    "name": stringProperty("Actor name"),
                    "role": stringProperty("Short role description")
                ],
                required: ["project_id", "name"]
            ),
            tool(
                "update_actor",
                "Update an actor name or role.",
                properties: actorIdentifiers.merging([
                    "name": stringProperty("New actor name"),
                    "role": stringProperty("New role description")
                ]) { _, new in new },
                required: ["project_id", "actor_id"]
            ),
            tool(
                "delete_actor",
                "Permanently delete an unused actor. Requires explicit confirmation.",
                properties: actorIdentifiers.merging(confirmProperty) { _, new in new },
                required: ["project_id", "actor_id", "confirm"]
            ),
            tool(
                "list_stories",
                "List or search stories by project, actor, status, creation date, text, or open criteria.",
                properties: [
                    "project_id": stringProperty("Project UUID"),
                    "actor_id": stringProperty("Actor UUID"),
                    "status": enumProperty(["draft", "active", "done"]),
                    "query": stringProperty("Search title, story text, notes, actor, and criteria"),
                    "created_after": stringProperty("ISO 8601 date-time or YYYY-MM-DD, inclusive"),
                    "created_before": stringProperty("ISO 8601 date-time or YYYY-MM-DD, inclusive"),
                    "has_open_criteria": boolProperty("Whether the story has unmet criteria")
                ]
            ),
            tool(
                "get_story",
                "Read a complete story.",
                properties: identifiers,
                required: ["project_id", "story_id"]
            ),
            tool(
                "duplicate_story",
                "Duplicate a story as a new draft with unchecked criteria.",
                properties: identifiers,
                required: ["project_id", "story_id"]
            ),
            tool(
                "delete_story",
                "Permanently delete a story, criteria, and attachments. Requires explicit confirmation.",
                properties: identifiers.merging(confirmProperty) { _, new in new },
                required: ["project_id", "story_id", "confirm"]
            ),
            tool(
                "create_story",
                "Create a draft story in a local project.",
                properties: [
                    "project_id": stringProperty("Project UUID"),
                    "title": stringProperty("Story title"),
                    "actor_id": stringProperty("Actor UUID"),
                    "want": stringProperty("What the actor needs"),
                    "outcome": stringProperty("Why the need matters"),
                    "acceptance_criteria": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")])
                    ])
                ],
                required: ["project_id", "title", "actor_id", "want", "outcome", "acceptance_criteria"]
            ),
            tool(
                "update_story",
                "Update the core fields of a non-completed story.",
                properties: identifiers.merging([
                    "title": stringProperty("New title"),
                    "actor_id": stringProperty("New actor UUID"),
                    "want": stringProperty("Updated need"),
                    "outcome": stringProperty("Updated outcome")
                ]) { _, new in new },
                required: ["project_id", "story_id"]
            ),
            tool(
                "add_acceptance_criterion",
                "Add an acceptance criterion to a non-completed story.",
                properties: identifiers.merging(["text": stringProperty("Criterion text")]) { _, new in new },
                required: ["project_id", "story_id", "text"]
            ),
            tool(
                "set_acceptance_criterion",
                "Mark an acceptance criterion as met or not met.",
                properties: identifiers.merging([
                    "criterion_id": stringProperty("Criterion UUID"),
                    "is_met": .object(["type": .string("boolean")])
                ]) { _, new in new },
                required: ["project_id", "story_id", "criterion_id", "is_met"]
            ),
            tool(
                "delete_acceptance_criterion",
                "Permanently delete a criterion. Requires explicit confirmation.",
                properties: identifiers.merging([
                    "criterion_id": stringProperty("Criterion UUID")
                ]) { _, new in new }.merging(confirmProperty) { _, new in new },
                required: ["project_id", "story_id", "criterion_id", "confirm"]
            ),
            tool(
                "set_story_status",
                "Change story status. All criteria must be met before using done.",
                properties: identifiers.merging([
                    "status": enumProperty(["draft", "active", "done"])
                ]) { _, new in new },
                required: ["project_id", "story_id", "status"]
            ),
            tool(
                "update_notes",
                "Replace the single notes field of a non-completed story.",
                properties: identifiers.merging(["notes": stringProperty("Story notes")]) { _, new in new },
                required: ["project_id", "story_id", "notes"]
            ),
            tool(
                "list_attachments",
                "List story attachments and local URLs available while the app is running.",
                properties: identifiers,
                required: ["project_id", "story_id"]
            ),
            tool(
                "add_attachments",
                "Copy local files into a story. Limits: 10 files, 10 MB each, 50 MB total.",
                properties: identifiers.merging([
                    "paths": arrayProperty("Absolute local file paths", itemType: "string")
                ]) { _, new in new },
                required: ["project_id", "story_id", "paths"]
            ),
            tool(
                "get_attachment",
                "Get attachment metadata and its temporary local HTTP URL.",
                properties: attachmentIdentifiers,
                required: ["project_id", "story_id", "attachment_id"]
            ),
            tool(
                "delete_attachment",
                "Permanently delete an attachment. Requires explicit confirmation.",
                properties: attachmentIdentifiers.merging(confirmProperty) { _, new in new },
                required: ["project_id", "story_id", "attachment_id", "confirm"]
            )
        ]
    }

    static var identifiers: [String: JSONValue] {
        [
            "project_id": stringProperty("Project UUID"),
            "story_id": stringProperty("Story UUID")
        ]
    }

    static var actorIdentifiers: [String: JSONValue] {
        [
            "project_id": stringProperty("Project UUID"),
            "actor_id": stringProperty("Actor UUID")
        ]
    }

    static var attachmentIdentifiers: [String: JSONValue] {
        identifiers.merging([
            "attachment_id": stringProperty("Attachment UUID")
        ]) { _, new in new }
    }

    static var confirmProperty: [String: JSONValue] {
        ["confirm": boolProperty("Must be true after explicit user approval")]
    }

    static func tool(
        _ name: String,
        _ description: String,
        properties: [String: JSONValue],
        required: [String] = []
    ) -> JSONValue {
        var schema: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object(properties),
            "additionalProperties": .bool(false)
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map(JSONValue.string))
        }
        return .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": .object(schema)
        ])
    }

    static func stringProperty(_ description: String) -> JSONValue {
        .object(["type": .string("string"), "description": .string(description)])
    }

    static func boolProperty(_ description: String) -> JSONValue {
        .object(["type": .string("boolean"), "description": .string(description)])
    }

    static func arrayProperty(_ description: String, itemType: String) -> JSONValue {
        .object([
            "type": .string("array"),
            "description": .string(description),
            "items": .object(["type": .string(itemType)])
        ])
    }

    static func enumProperty(_ values: [String]) -> JSONValue {
        .object([
            "type": .string("string"),
            "enum": .array(values.map(JSONValue.string))
        ])
    }
}
