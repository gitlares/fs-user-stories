// SPDX-License-Identifier: MIT

import XCTest
@testable import FSUserStoriesApp

@MainActor
final class StoryMarkdownTransferTests: XCTestCase {
    func testMarkdownRoundTripPreservesStoryDataWithoutAttachments() throws {
        let actor = ProjectActor(name: "Developer", role: "Builds the product")
        let attachment = StoryAttachment(
            filename: "mockup.png",
            contentType: "image/png",
            byteSize: 42,
            sha256: "hash",
            relativePath: "ignored"
        )
        let story = UserStory(
            number: 7,
            title: "Export stories",
            actorID: actor.id,
            want: "one Markdown file",
            outcome: "I can share the plan",
            notes: "Keep it simple.",
            acceptanceCriteria: [AcceptanceCriterion(text: "Exports criteria", isMet: true)],
            attachments: [attachment],
            status: .active,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let project = FSProject(
            name: "Example",
            prefix: "EX",
            actors: [actor],
            stories: [story]
        )

        let exported = try StoryMarkdownTransfer.document(project: project, storyIDs: [story.id])
        let markdown = try StoryMarkdownTransfer.markdown(for: exported)
        let imported = try StoryMarkdownTransfer.parse(markdown)

        XCTAssertEqual(imported.stories, exported.stories)
        XCTAssertTrue(markdown.contains("## EX-7 — Export stories"))
        XCTAssertFalse(markdown.contains("mockup.png"))
    }

    func testImportCreatesProfilesAndNewStoryNumbersWithoutAttachments() throws {
        let targetActor = ProjectActor(name: "Existing", role: "Existing profile")
        let existingStory = UserStory(
            number: 4,
            title: "Existing story",
            actorID: targetActor.id,
            want: "stay",
            outcome: "nothing is overwritten",
            acceptanceCriteria: [AcceptanceCriterion(text: "Remains")]
        )
        let project = FSProject(
            name: "Target",
            prefix: "TGT",
            actors: [targetActor],
            stories: [existingStory]
        )
        let store = AppStore(projects: [project])
        let portable = PortableStory(
            id: UUID(),
            originalReference: "SRC-2",
            title: "Imported story",
            profileName: "Product Owner",
            profileDescription: "Defines the need",
            want: "import stories",
            outcome: "migration is simple",
            notes: "No attachments.",
            acceptanceCriteria: [AcceptanceCriterion(text: "Imports", isMet: true)],
            status: .done,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let result = store.importStories([portable], to: project.id)

        XCTAssertEqual(try result.get(), 1)
        let importedStory = try XCTUnwrap(store.projects[0].stories.last)
        XCTAssertEqual(importedStory.number, 5)
        XCTAssertEqual(importedStory.status, .done)
        XCTAssertTrue(importedStory.attachments.isEmpty)
        XCTAssertEqual(store.projects[0].actors.last?.name, "Product Owner")
    }
}
