// SPDX-License-Identifier: MIT

import Foundation
import XCTest
@testable import FSUserStoriesApp

@MainActor
final class RustWorkspacePersistenceTests: XCTestCase {
    func testRustPersistsProjectProfileAndStoryCRUD() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "FSUserStories-RustCRUD-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let persistenceStore = try PersistenceStore(
            databaseURL: directory.appending(path: "FSUserStories.sqlite3")
        )
        let appStore = AppStore(projects: [], persistenceStore: persistenceStore)
        let project = try unwrap(appStore.createProject(name: "Rust Core", prefix: "RUST"))
        let actor = try unwrap(appStore.addActor(name: "Developer", role: "Builds", to: project.id))
        let story = try unwrap(appStore.addStory(
            title: "Create through Rust",
            actorID: actor.id,
            want: "all CRUD in the core",
            outcome: "Swift stays a UI",
            acceptanceCriteria: [AcceptanceCriterion(text: "It persists")],
            to: project.id
        ))
        _ = try unwrap(appStore.duplicateStory(story.id, projectID: project.id))

        let reloadedProject = try XCTUnwrap(persistenceStore.loadProjects().first)
        XCTAssertEqual(reloadedProject.name, "Rust Core")
        XCTAssertEqual(reloadedProject.actors, [actor])
        XCTAssertEqual(reloadedProject.stories.count, 2)
    }

    func testRustOwnsTheSingleSQLiteDatabaseForStoryLifecycleChanges() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "FSUserStories-RustSQLite-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let databaseURL = directory.appending(path: "FSUserStories.sqlite3")
        let actor = ProjectActor(name: "Developer", role: "Builds the product")
        let criterion = AcceptanceCriterion(text: "The core persists the change")
        let story = UserStory(
            number: 1,
            title: "Persist through Rust",
            actorID: actor.id,
            want: "one SQLite owner",
            outcome: "no replicated database",
            acceptanceCriteria: [criterion],
            status: .active
        )
        let project = FSProject(name: "Example", prefix: "EX", actors: [actor], stories: [story])

        let persistenceStore = try PersistenceStore(databaseURL: databaseURL)
        try persistenceStore.save([project])
        let appStore = AppStore(projects: try persistenceStore.loadProjects(), persistenceStore: persistenceStore)

        guard case .success = appStore.setAcceptanceCriterion(
            criterion.id,
            isMet: true,
            in: story.id,
            projectID: project.id
        ) else {
            return XCTFail("The Rust-backed criterion change should succeed")
        }
        guard case .success = appStore.setStoryStatus(.done, for: story.id, projectID: project.id) else {
            return XCTFail("The Rust-backed completion should succeed")
        }

        let reloadedStory = try XCTUnwrap(
            persistenceStore.loadProjects().first?.stories.first
        )
        XCTAssertTrue(reloadedStory.acceptanceCriteria[0].isMet)
        XCTAssertEqual(reloadedStory.status, .done)
        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    func testDeletingProjectRemovesItsPersistedDataAndManagedAttachments() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "FSUserStories-DeleteProject-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let databaseURL = directory.appending(path: "FSUserStories.sqlite3")
        let attachmentStorage = try AttachmentStorage(rootURL: directory.appending(path: "Attachments"))
        let actor = ProjectActor(name: "Developer", role: "Builds")
        let projectID = UUID()
        let storyID = UUID()
        let attachment = StoryAttachment(
            filename: "brief.txt",
            contentType: "text/plain",
            byteSize: 5,
            sha256: "digest",
            relativePath: "\(projectID.uuidString)/\(storyID.uuidString)/brief.txt"
        )
        let story = UserStory(
            id: storyID,
            number: 1,
            title: "Delete me",
            actorID: actor.id,
            want: "cleanup",
            outcome: "nothing remains locally",
            attachments: [attachment]
        )
        let project = FSProject(
            id: projectID,
            name: "Disposable",
            prefix: "DEL",
            actors: [actor],
            stories: [story]
        )
        let attachmentURL = attachmentStorage.url(for: attachment)
        try FileManager.default.createDirectory(
            at: attachmentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("brief".utf8).write(to: attachmentURL)

        let persistenceStore = try PersistenceStore(databaseURL: databaseURL)
        try persistenceStore.save([project])
        let appStore = AppStore(
            projects: try persistenceStore.loadProjects(),
            persistenceStore: persistenceStore,
            attachmentStorage: attachmentStorage
        )

        guard case .success = appStore.deleteProject(projectID) else {
            return XCTFail("The project should be deleted")
        }
        XCTAssertTrue(appStore.projects.isEmpty)
        XCTAssertTrue(try persistenceStore.loadProjects().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: attachmentURL.path))
    }

    private func unwrap<T>(_ result: Result<T, WorkspaceError>) throws -> T {
        switch result {
        case let .success(value): value
        case let .failure(error): throw error
        }
    }
}
