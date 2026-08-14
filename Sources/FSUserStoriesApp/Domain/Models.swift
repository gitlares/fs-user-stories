// SPDX-License-Identifier: MIT

import Foundation

struct ProjectActor: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var role: String

    init(id: UUID = UUID(), name: String, role: String) {
        self.id = id
        self.name = name
        self.role = role
    }
}

enum StoryStatus: String, CaseIterable, Identifiable, Codable, Sendable {
    case draft
    case active
    case done

    var id: Self { self }

    var localizedName: String {
        switch self {
        case .draft:
            L10n.string("Draft")
        case .active:
            L10n.string("Active")
        case .done:
            L10n.string("Done")
        }
    }
}

struct AcceptanceCriterion: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var text: String
    var isMet: Bool

    init(id: UUID = UUID(), text: String, isMet: Bool = false) {
        self.id = id
        self.text = text
        self.isMet = isMet
    }
}

struct StoryAttachment: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var filename: String
    var contentType: String
    var byteSize: Int64
    var sha256: String
    var relativePath: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        filename: String,
        contentType: String,
        byteSize: Int64,
        sha256: String,
        relativePath: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.filename = filename
        self.contentType = contentType
        self.byteSize = byteSize
        self.sha256 = sha256
        self.relativePath = relativePath
        self.createdAt = createdAt
    }
}

struct UserStory: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let number: Int
    var title: String
    var actorID: UUID
    var want: String
    var outcome: String
    var notes: String
    var acceptanceCriteria: [AcceptanceCriterion]
    var attachments: [StoryAttachment]
    var status: StoryStatus
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, number, title, want, outcome, notes, acceptanceCriteria, attachments, status, createdAt
        case actorID = "actorId"
    }

    init(
        id: UUID = UUID(),
        number: Int,
        title: String,
        actorID: UUID,
        want: String,
        outcome: String,
        notes: String = "",
        acceptanceCriteria: [AcceptanceCriterion] = [],
        attachments: [StoryAttachment] = [],
        status: StoryStatus = .draft,
        createdAt: Date = .now
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.actorID = actorID
        self.want = want
        self.outcome = outcome
        self.notes = notes
        self.acceptanceCriteria = acceptanceCriteria
        self.attachments = attachments
        self.status = status
        self.createdAt = createdAt
    }
}

extension UserStory {
    var metCriteriaCount: Int {
        acceptanceCriteria.count(where: \.isMet)
    }

    var criteriaProgress: Double {
        guard !acceptanceCriteria.isEmpty else { return 0 }
        return Double(metCriteriaCount) / Double(acceptanceCriteria.count)
    }
}

struct FSProject: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var prefix: String
    var actors: [ProjectActor]
    var stories: [UserStory]
    var gitRepository: GitRepositoryLink?

    init(
        id: UUID = UUID(),
        name: String,
        prefix: String,
        actors: [ProjectActor] = [],
        stories: [UserStory] = [],
        gitRepository: GitRepositoryLink? = nil
    ) {
        self.id = id
        self.name = name
        self.prefix = prefix
        self.actors = actors
        self.stories = stories
        self.gitRepository = gitRepository
    }
}

struct GitRepositoryLink: Codable, Hashable, Sendable {
    var localPath: String
    var remoteURL: String?
    var defaultBranch: String
    var lastSyncedDigest: String?
    var lastSyncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case localPath, defaultBranch, lastSyncedDigest, lastSyncedAt
        case remoteURL = "remoteUrl"
    }

    init(
        localPath: String,
        remoteURL: String? = nil,
        defaultBranch: String = "fs-user-stories",
        lastSyncedDigest: String? = nil,
        lastSyncedAt: Date? = nil
    ) {
        self.localPath = localPath
        self.remoteURL = remoteURL
        self.defaultBranch = defaultBranch
        self.lastSyncedDigest = lastSyncedDigest
        self.lastSyncedAt = lastSyncedAt
    }
}
