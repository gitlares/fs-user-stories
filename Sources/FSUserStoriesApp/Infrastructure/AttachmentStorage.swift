// SPDX-License-Identifier: MIT

import CryptoKit
import Foundation
import UniformTypeIdentifiers

enum AttachmentStorageError: Error {
    case fileTooLarge(String)
    case notAFile(String)
}

final class AttachmentStorage {
    static let maximumFileSize: Int64 = 10 * 1_024 * 1_024
    static let maximumFilesPerStory = 10
    static let maximumStorySize: Int64 = 50 * 1_024 * 1_024

    private let rootURL: URL

    init(rootURL: URL? = nil) throws {
        self.rootURL = try rootURL ?? Self.defaultRootURL()
        try FileManager.default.createDirectory(
            at: self.rootURL,
            withIntermediateDirectories: true
        )
    }

    func preflight(_ url: URL) throws -> (filename: String, byteSize: Int64) {
        try withSecurityScopedAccess(to: url) {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            let filename = url.lastPathComponent
            guard values.isRegularFile == true else {
                throw AttachmentStorageError.notAFile(filename)
            }

            let byteSize = Int64(values.fileSize ?? 0)
            guard byteSize <= Self.maximumFileSize else {
                throw AttachmentStorageError.fileTooLarge(filename)
            }
            return (filename, byteSize)
        }
    }

    func importFile(from url: URL, projectID: UUID, storyID: UUID) throws -> StoryAttachment {
        try withSecurityScopedAccess(to: url) {
            let filename = url.lastPathComponent
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard Int64(data.count) <= Self.maximumFileSize else {
                throw AttachmentStorageError.fileTooLarge(filename)
            }

            let attachmentID = UUID()
            let safeFilename = sanitizedFilename(filename)
            let relativePath = [
                projectID.uuidString,
                storyID.uuidString,
                "\(attachmentID.uuidString)-\(safeFilename)"
            ].joined(separator: "/")
            let destinationURL = rootURL.appending(path: relativePath)

            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destinationURL, options: .atomic)

            return StoryAttachment(
                id: attachmentID,
                filename: filename,
                contentType: UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.data.identifier,
                byteSize: Int64(data.count),
                sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                relativePath: relativePath
            )
        }
    }

    func restoreFile(
        from url: URL,
        metadata: GitProjectSnapshot.Attachment,
        projectID: UUID,
        storyID: UUID
    ) throws -> StoryAttachment {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard Int64(data.count) <= Self.maximumFileSize else {
            throw AttachmentStorageError.fileTooLarge(metadata.filename)
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == metadata.sha256 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let relativePath = [
            projectID.uuidString,
            storyID.uuidString,
            "\(metadata.id.uuidString)-\(sanitizedFilename(metadata.filename))"
        ].joined(separator: "/")
        let destinationURL = rootURL.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try data.write(to: destinationURL, options: .atomic)
        return StoryAttachment(
            id: metadata.id,
            filename: metadata.filename,
            contentType: metadata.contentType,
            byteSize: Int64(data.count),
            sha256: digest,
            relativePath: relativePath,
            createdAt: metadata.createdAt
        )
    }

    func url(for attachment: StoryAttachment) -> URL {
        rootURL.appending(path: attachment.relativePath)
    }

    func remove(_ attachment: StoryAttachment) throws {
        let fileURL = url(for: attachment)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    func removeStoryDirectory(projectID: UUID, storyID: UUID) throws {
        let directory = rootURL
            .appending(path: projectID.uuidString, directoryHint: .isDirectory)
            .appending(path: storyID.uuidString, directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
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

    private func withSecurityScopedAccess<T>(to url: URL, operation: () throws -> T) throws -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try operation()
    }

    private func sanitizedFilename(_ filename: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_ "))
        let sanitizedScalars = filename.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(String(scalar)) : "_"
        }
        let sanitized = String(sanitizedScalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "attachment" : sanitized
    }
}
