// SPDX-License-Identifier: MIT

import SwiftUI

struct StoryDetailView: View {
    @State private var isAddingCriterion = false
    @State private var newCriterionText = ""
    @State private var showsDeleteStoryConfirmation = false
    @State private var notesText = ""
    @State private var notesAreExpanded = false
    private let criterionEditorAnchor = "new-criterion-editor"

    let story: UserStory
    let project: FSProject
    let actor: ProjectActor?
    let setStatus: (StoryStatus) -> Void
    let toggleCriterion: (UUID) -> Void
    let addCriterion: (String) -> Void
    let editStory: () -> Void
    let duplicateStory: () -> Void
    let deleteStory: () -> Void
    let deleteCriterion: (UUID) -> Void
    let updateNotes: (String) -> Void
    let addAttachments: ([URL]) -> String?
    let attachmentURL: (StoryAttachment) -> URL?
    let deleteAttachment: (UUID) -> String?

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    storyStatement
                    acceptanceCriteria
                    completionProgress
                    notesSection
                    AttachmentsSection(
                        attachments: story.attachments,
                        isEditable: isEditable,
                        addFiles: addAttachments,
                        fileURL: attachmentURL,
                        deleteFile: deleteAttachment
                    )
                    completionAction
                    metadata
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(36)
            }
            .onChange(of: isAddingCriterion) {
                guard isAddingCriterion else { return }
                Task { @MainActor in
                    await Task.yield()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scrollProxy.scrollTo(criterionEditorAnchor, anchor: .center)
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: story.id) {
            notesText = story.notes
            notesAreExpanded = !story.notes.isEmpty
        }
        .onChange(of: story.status) {
            if story.status == .done {
                cancelAddingCriterion()
                notesText = story.notes
            }
        }
        .alert(
            L10n.string("Delete Story?"),
            isPresented: $showsDeleteStoryConfirmation
        ) {
            Button(L10n.string("Delete Story"), role: .destructive, action: deleteStory)
            Button(L10n.string("Cancel"), role: .cancel) {}
        } message: {
            Text(
                L10n.string(
                    "Deleting this story will permanently remove it, its acceptance criteria, and its attachments. This cannot be undone."
                )
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(project.prefix)-\(story.number)")
                    .font(.callout.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker(
                    L10n.string("Status"),
                    selection: Binding(
                        get: { story.status },
                        set: { newStatus in
                            setStatus(newStatus)
                        }
                    )
                ) {
                    ForEach(StoryStatus.allCases) { status in
                        Text(status.localizedName).tag(status)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .help(L10n.string("Change status"))
                .accessibilityLabel(L10n.string("Status"))

                Spacer()

                Button(action: editStory) {
                    Label(L10n.string("Edit Story"), systemImage: "pencil")
                }
                .buttonStyle(.glass)
                .disabled(!isEditable)
                .help(L10n.string("Edit Story"))

                Menu {
                    Button(action: editStory) {
                        Label(L10n.string("Edit Story"), systemImage: "pencil")
                    }
                    .disabled(!isEditable)

                    Button(action: duplicateStory) {
                        Label(L10n.string("Duplicate Story"), systemImage: "plus.square.on.square")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showsDeleteStoryConfirmation = true
                    } label: {
                        Label(L10n.string("Delete Story"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .menuIndicator(.hidden)
                .menuStyle(.borderlessButton)
                .help(L10n.string("Story Actions"))
                .accessibilityLabel(L10n.string("Story Actions"))
            }

            Text(story.title)
                .font(.largeTitle.weight(.semibold))
                .textSelection(.enabled)

            if !isEditable {
                Label(
                    L10n.string("Completed stories are read-only. Change status to Active or Draft to edit."),
                    systemImage: "lock.fill"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var storyStatement: some View {
        VStack(alignment: .leading, spacing: 18) {
            StatementLine(
                label: L10n.string("As"),
                value: actor?.name ?? L10n.string("Unknown actor")
            )
            StatementLine(label: L10n.string("I want"), value: story.want)
            StatementLine(label: L10n.string("So that"), value: story.outcome)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    notesAreExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(notesAreExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)

                    Text(L10n.string("Notes"))
                        .font(.title3.weight(.semibold))

                    Spacer()

                    if story.notes.isEmpty {
                        Text(L10n.string("Optional"))
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if notesAreExpanded {
                if isEditable {
                    MultilineTextArea(
                        prompt: L10n.string("Add context, constraints, decisions, or references"),
                        text: $notesText,
                        height: 120
                    )

                    HStack {
                        if hasUnsavedNotes {
                            Text(L10n.string("Unsaved changes"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(L10n.string("Save Notes")) {
                            notesText = normalizedNotes
                            updateNotes(notesText)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(!hasUnsavedNotes)
                    }
                } else {
                    Text(story.notes.isEmpty ? L10n.string("No notes") : story.notes)
                        .foregroundStyle(story.notes.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var normalizedNotes: String {
        notesText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasUnsavedNotes: Bool {
        normalizedNotes != story.notes
    }

    private var acceptanceCriteria: some View {
        VStack(alignment: .leading, spacing: 16) {
            criteriaHeader

            VStack(spacing: 0) {
                ForEach(Array(story.acceptanceCriteria.enumerated()), id: \.element.id) { index, criterion in
                    CriterionRow(
                        criterion: criterion,
                        isEditable: isEditable,
                        toggle: { toggleCriterion(criterion.id) },
                        delete: { deleteCriterion(criterion.id) }
                    )

                    if index < story.acceptanceCriteria.count - 1 {
                        Divider()
                            .padding(.leading, 32)
                    }
                }

                if story.acceptanceCriteria.isEmpty && !isAddingCriterion {
                    Text(L10n.string("No acceptance criteria yet."))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                }

                if isAddingCriterion {
                    if !story.acceptanceCriteria.isEmpty {
                        Divider()
                            .padding(.leading, 32)
                    }
                    criterionEditor
                        .id(criterionEditorAnchor)
                }
            }
        }
    }

    private var criteriaHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(L10n.string("Acceptance Criteria"))
                .font(.title3.weight(.semibold))

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isAddingCriterion = true
                }
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .help(L10n.string("Add Criterion"))
            .accessibilityLabel(L10n.string("Add Criterion"))
            .disabled(!isEditable)
        }
    }

    private var completionProgress: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.string("Completion"))
                    .font(.title3.weight(.semibold))

                Spacer()

                Text("\(completionPercentage)%")
                    .font(.title2.monospacedDigit().weight(.semibold))
            }

            ProgressView(value: story.criteriaProgress)
                .progressViewStyle(.linear)
                .tint(completionPercentage == 100 ? .green : .accentColor)

            Text(criteriaProgressText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.string("Acceptance progress"))
        .accessibilityValue("\(completionPercentage)%, \(criteriaProgressText)")
    }

    @ViewBuilder
    private var completionAction: some View {
        if canMarkAsCompleted {
            VStack(alignment: .leading, spacing: 12) {
                Divider()

                Button {
                    setStatus(.done)
                } label: {
                    Label(L10n.string("Mark as Completed"), systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .accessibilityHint(
                    L10n.string("All acceptance criteria are met. Change this story to Done.")
                )
            }
        }
    }

    private var criterionEditor: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .accessibilityHidden(true)

            MultilineTextArea(
                prompt: L10n.string("Expected result"),
                text: $newCriterionText,
                height: 68,
                automaticallyFocus: true
            )

            Button {
                cancelAddingCriterion()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
            .accessibilityLabel(L10n.string("Cancel"))

            Button {
                saveCriterion()
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .padding(.top, 8)
            .disabled(newCriterionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(L10n.string("Save criterion"))
        }
        .padding(.vertical, 12)
    }

    private var criteriaProgressText: String {
        L10n.criterionProgress(
            met: story.metCriteriaCount,
            total: story.acceptanceCriteria.count
        )
    }

    private var completionPercentage: Int {
        Int((story.criteriaProgress * 100).rounded())
    }

    private var canMarkAsCompleted: Bool {
        story.status == .active &&
            !story.acceptanceCriteria.isEmpty &&
            story.metCriteriaCount == story.acceptanceCriteria.count
    }

    private var isEditable: Bool {
        story.status != .done
    }

    private func saveCriterion() {
        let trimmedText = newCriterionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        addCriterion(trimmedText)
        newCriterionText = ""
        withAnimation(.easeInOut(duration: 0.2)) {
            isAddingCriterion = false
        }
    }

    private func cancelAddingCriterion() {
        newCriterionText = ""
        withAnimation(.easeInOut(duration: 0.2)) {
            isAddingCriterion = false
        }
    }

    private var metadata: some View {
        HStack(spacing: 28) {
            Label(project.name, systemImage: "rectangle.stack")
            if let actor {
                Label(actor.name, systemImage: "person")
            }
            Label(story.createdAt.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

private struct CriterionRow: View {
    @State private var isHovering = false
    @State private var showsDeleteConfirmation = false

    let criterion: AcceptanceCriterion
    let isEditable: Bool
    let toggle: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: toggle) {
                Image(systemName: criterion.isMet ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(criterion.isMet ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!isEditable)
            .accessibilityLabel(
                criterion.isMet
                    ? L10n.string("Mark as not met")
                    : L10n.string("Mark as met")
            )

            Text(criterion.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .strikethrough(criterion.isMet, color: .secondary)
                .foregroundStyle(criterion.isMet ? .secondary : .primary)

            Button {
                showsDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isEditable && isHovering ? 1 : 0)
            .disabled(!isEditable)
            .accessibilityLabel(L10n.string("Delete criterion"))
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            if isEditable {
                Button(L10n.string("Delete criterion"), role: .destructive) {
                    showsDeleteConfirmation = true
                }
            }
        }
        .alert(
            L10n.string("Delete Criterion?"),
            isPresented: $showsDeleteConfirmation
        ) {
            Button(L10n.string("Delete criterion"), role: .destructive, action: delete)
            Button(L10n.string("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("This acceptance criterion will be permanently deleted."))
        }
    }
}

private struct StatementLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text(label)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)

            Text(value)
                .font(.title3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
