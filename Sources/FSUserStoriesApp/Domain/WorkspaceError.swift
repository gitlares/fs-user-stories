// SPDX-License-Identifier: MIT

import Foundation

enum WorkspaceError: LocalizedError, Equatable {
    case projectNotFound
    case actorNotFound
    case storyNotFound
    case criterionNotFound
    case attachmentNotFound
    case nameRequired
    case prefixRequired
    case titleRequired
    case wantRequired
    case outcomeRequired
    case acceptanceCriterionRequired
    case actorInUse
    case completedStoryReadOnly
    case incompleteAcceptanceCriteria
    case attachmentsRequired
    case attachmentFailure(String)
    case persistenceFailure(String)

    var errorDescription: String? {
        switch self {
        case .projectNotFound: "Project not found"
        case .actorNotFound: "Actor not found"
        case .storyNotFound: "Story not found"
        case .criterionNotFound: "Acceptance criterion not found"
        case .attachmentNotFound: "Attachment not found"
        case .nameRequired: "A name is required"
        case .prefixRequired: "A project prefix is required"
        case .titleRequired: "A story title is required"
        case .wantRequired: "The story need is required"
        case .outcomeRequired: "The story outcome is required"
        case .acceptanceCriterionRequired: "At least one acceptance criterion is required"
        case .actorInUse: "An actor used by stories cannot be deleted"
        case .completedStoryReadOnly:
            "Completed stories are read-only. Reopen the story before editing it."
        case .incompleteAcceptanceCriteria:
            "All acceptance criteria must be met before completing a story"
        case .attachmentsRequired: "At least one attachment is required"
        case let .attachmentFailure(message), let .persistenceFailure(message): message
        }
    }
}
