// SPDX-License-Identifier: MIT

import Foundation

final class AttachmentStorage {
    static let maximumFilesPerStory = 10

    let rootURL: URL

    init(rootURL: URL? = nil) throws {
        self.rootURL = try rootURL ?? Self.defaultRootURL()
        try FileManager.default.createDirectory(
            at: self.rootURL,
            withIntermediateDirectories: true
        )
    }

    func withSecurityScopedAccess<T>(to urls: [URL], operation: () throws -> T) throws -> T {
        let accessedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }
        return try operation()
    }

    func url(for attachment: StoryAttachment) -> URL {
        rootURL.appending(path: attachment.relativePath)
    }

    private static func defaultRootURL() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport
            .appending(path: "FS User Stories", directoryHint: .isDirectory)
            .appending(path: "Attachments", directoryHint: .isDirectory)
    }

}
