// SPDX-License-Identifier: MIT

import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct AttachmentsSection: View {
    let attachments: [StoryAttachment]
    let isEditable: Bool
    let addFiles: ([URL]) -> String?
    let fileURL: (StoryAttachment) -> URL?
    let deleteFile: (UUID) -> String?

    @State private var showsFileImporter = false
    @State private var previewURL: URL?
    @State private var errorMessage: String?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.string("Attachments"))
                    .font(.title3.weight(.semibold))

                if !attachments.isEmpty {
                    Text("\(attachments.count)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showsFileImporter = true
                } label: {
                    Image(systemName: "paperclip")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(!isEditable || attachments.count >= AttachmentStorage.maximumFilesPerStory)
                .help(L10n.string("Add Attachments"))
                .accessibilityLabel(L10n.string("Add Attachments"))
            }

            if attachments.isEmpty {
                emptyDropZone
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                        AttachmentRow(
                            attachment: attachment,
                            isEditable: isEditable,
                            preview: { preview(attachment) },
                            delete: { delete(attachment) }
                        )

                        if index < attachments.count - 1 {
                            Divider()
                                .padding(.leading, 42)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(.background.secondary, in: .rect(cornerRadius: 14))

                compactDropZone
            }

            Text(L10n.string("Up to 10 files • 10 MB each • 50 MB total"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear,
            in: .rect(cornerRadius: 18)
        )
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard isEditable else { return false }
            handle(urls)
            return true
        } isTargeted: { isTargeted in
            isDropTargeted = isEditable && isTargeted
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                handle(urls)
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
        .quickLookPreview($previewURL)
        .alert(
            L10n.string("Attachment Error"),
            isPresented: errorIsPresented
        ) {
            Button(L10n.string("OK"), role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var emptyDropZone: some View {
        Button {
            showsFileImporter = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "paperclip")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.tint)

                Text(L10n.string("Drop files here or choose files"))
                    .font(.headline)

                Text(L10n.string("Images, documents, and other project files"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.separator, style: StrokeStyle(lineWidth: 1, dash: [5]))
        }
    }

    private var compactDropZone: some View {
        Button {
            showsFileImporter = true
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "arrow.down.doc")
                    .foregroundStyle(.tint)

                Text(L10n.string("Drop more files here or choose files"))
                    .font(.callout)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEditable || attachments.count >= AttachmentStorage.maximumFilesPerStory)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator, style: StrokeStyle(lineWidth: 1, dash: [5]))
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private func handle(_ urls: [URL]) {
        errorMessage = addFiles(urls)
    }

    private func preview(_ attachment: StoryAttachment) {
        guard let url = fileURL(attachment) else {
            errorMessage = L10n.string("The attachment file could not be found.")
            return
        }
        previewURL = url
    }

    private func delete(_ attachment: StoryAttachment) {
        errorMessage = deleteFile(attachment.id)
    }
}

private struct AttachmentRow: View {
    let attachment: StoryAttachment
    let isEditable: Bool
    let preview: () -> Void
    let delete: () -> Void

    @State private var showsDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 26)

            Button(action: preview) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(attachment.filename)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Text(ByteCountFormatter.string(fromByteCount: attachment.byteSize, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button(action: preview) {
                Image(systemName: "eye")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L10n.string("Quick Look"))

            Button {
                showsDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L10n.string("Delete Attachment"))
            .disabled(!isEditable)
            .opacity(isEditable ? 1 : 0)
        }
        .padding(.vertical, 10)
        .contextMenu {
            Button(action: preview) {
                Label(L10n.string("Quick Look"), systemImage: "eye")
            }

            if isEditable {
                Divider()

                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Label(L10n.string("Delete Attachment"), systemImage: "trash")
                }
            }
        }
        .alert(
            L10n.string("Delete Attachment?"),
            isPresented: $showsDeleteConfirmation
        ) {
            Button(L10n.string("Delete Attachment"), role: .destructive, action: delete)
            Button(L10n.string("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("This file will be permanently removed from the story."))
        }
    }

    private var iconName: String {
        guard let type = UTType(attachment.contentType) else { return "doc" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .movie) { return "film" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .archive) { return "archivebox" }
        return "doc"
    }
}
