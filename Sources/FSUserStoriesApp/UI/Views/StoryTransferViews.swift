// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum StoryExportScope: String, CaseIterable, Identifiable {
    case all
    case active
    case completed
    case drafts
    case selected

    var id: Self { self }

    var localizedName: String {
        switch self {
        case .all: L10n.string("All Stories")
        case .active: L10n.string("Active Stories")
        case .completed: L10n.string("Completed Stories")
        case .drafts: L10n.string("Draft Stories")
        case .selected: L10n.string("Choose Stories")
        }
    }
}

struct StoryExportView: View {
    @Environment(\.dismiss) private var dismiss
    let project: FSProject
    @State private var scope: StoryExportScope = .all
    @State private var selectedStoryIDs: Set<UUID>
    @State private var errorMessage: String?

    init(project: FSProject, initiallySelectedStoryID: UUID?) {
        self.project = project
        _selectedStoryIDs = State(
            initialValue: initiallySelectedStoryID.map { [$0] } ?? []
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                Label(L10n.string("Export Stories"), systemImage: "square.and.arrow.up")
                    .font(.title.bold())

                Text(L10n.string("Create one Markdown file. Attachments are not included."))
                    .foregroundStyle(.secondary)

                Picker(L10n.string("Stories to Export"), selection: $scope) {
                    ForEach(StoryExportScope.allCases) { value in
                        Text(value.localizedName).tag(value)
                    }
                }
                .pickerStyle(.menu)

                if scope == .selected {
                    storySelection
                } else {
                    Label(exportCountText, systemImage: "doc.text")
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            .padding(28)

            Spacer()
            Divider()
            HStack {
                Button(L10n.string("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.string("Export…"), action: export)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(exportStoryIDs.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 560, height: 560)
    }

    private var storySelection: some View {
        List(project.stories.sorted { $0.createdAt > $1.createdAt }) { story in
            Toggle(isOn: selectionBinding(for: story.id)) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(project.prefix)-\(story.number) — \(story.title)")
                    Text(story.status.localizedName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
        }
        .listStyle(.inset)
        .frame(minHeight: 280)
    }

    private var exportStoryIDs: Set<UUID> {
        switch scope {
        case .all: Set(project.stories.map(\.id))
        case .active: Set(project.stories.filter { $0.status == .active }.map(\.id))
        case .completed: Set(project.stories.filter { $0.status == .done }.map(\.id))
        case .drafts: Set(project.stories.filter { $0.status == .draft }.map(\.id))
        case .selected: selectedStoryIDs
        }
    }

    private var exportCountText: String {
        L10n.storyCount(exportStoryIDs.count)
    }

    private func selectionBinding(for storyID: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedStoryIDs.contains(storyID) },
            set: { selected in
                if selected { selectedStoryIDs.insert(storyID) }
                else { selectedStoryIDs.remove(storyID) }
            }
        )
    }

    private func export() {
        do {
            let document = try StoryMarkdownTransfer.document(
                project: project,
                storyIDs: exportStoryIDs
            )
            let markdown = try StoryMarkdownTransfer.markdown(for: document)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
            panel.nameFieldStringValue = "\(project.name)-user-stories.md"
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct StoryImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let document: StoryMarkdownDocument
    let importStories: ([PortableStory]) -> Result<Int, WorkspaceError>
    @State private var selectedStoryIDs: Set<UUID>
    @State private var errorMessage: String?

    init(
        document: StoryMarkdownDocument,
        importStories: @escaping ([PortableStory]) -> Result<Int, WorkspaceError>
    ) {
        self.document = document
        self.importStories = importStories
        _selectedStoryIDs = State(initialValue: Set(document.stories.map(\.id)))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Label(L10n.string("Import Stories"), systemImage: "square.and.arrow.down")
                    .font(.title.bold())
                Text(String(format: L10n.string("Choose stories from %@. Attachments are not imported."), document.projectName))
                    .foregroundStyle(.secondary)

                List(document.stories) { story in
                    Toggle(isOn: selectionBinding(for: story.id)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(story.originalReference) — \(story.title)")
                            Text("\(story.profileName) • \(story.status.localizedName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                .listStyle(.inset)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            .padding(28)

            Divider()
            HStack {
                Button(L10n.string("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text(L10n.storyCount(selectedStories.count))
                    .foregroundStyle(.secondary)
                Button(L10n.string("Import"), action: performImport)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedStories.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 620, height: 600)
    }

    private var selectedStories: [PortableStory] {
        document.stories.filter { selectedStoryIDs.contains($0.id) }
    }

    private func selectionBinding(for storyID: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedStoryIDs.contains(storyID) },
            set: { selected in
                if selected { selectedStoryIDs.insert(storyID) }
                else { selectedStoryIDs.remove(storyID) }
            }
        )
    }

    private func performImport() {
        switch importStories(selectedStories) {
        case .success:
            dismiss()
        case let .failure(error):
            errorMessage = error.localizedDescription
        }
    }
}
