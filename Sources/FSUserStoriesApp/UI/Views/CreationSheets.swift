// SPDX-License-Identifier: MIT

import SwiftUI

struct NewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var prefix = ""
    @FocusState private var focusedField: Field?

    let onCreate: (String, String) -> Void

    private enum Field {
        case name
        case prefix
    }

    var body: some View {
        CreationSheetLayout(
            title: L10n.string("New Project"),
            subtitle: L10n.string("Create a focused workspace for your stories."),
            symbol: "rectangle.stack.badge.plus",
            isValid: isValid,
            actionTitle: L10n.string("Create Project"),
            cancel: { dismiss() },
            submit: create
        ) {
            Form {
                TextField(
                    L10n.string("Project name"),
                    text: $name,
                    prompt: Text(L10n.string("My Product"))
                )
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .name)

                TextField(
                    L10n.string("Story prefix"),
                    text: $prefix,
                    prompt: Text(L10n.string("MP"))
                )
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .prefix)
                    .textCase(.uppercase)
            }
            .formStyle(.grouped)
        }
        .onAppear { focusedField = .name }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func create() {
        guard isValid else { return }
        onCreate(name, prefix)
        dismiss()
    }
}

struct NewActorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var role: String
    @FocusState private var nameIsFocused: Bool

    private let profile: ProjectActor?
    let onSave: (String, String) -> Void

    init(profile: ProjectActor? = nil, onSave: @escaping (String, String) -> Void) {
        self.profile = profile
        self.onSave = onSave
        _name = State(initialValue: profile?.name ?? "")
        _role = State(initialValue: profile?.role ?? "")
    }

    var body: some View {
        CreationSheetLayout(
            title: L10n.string(profile == nil ? "Add Profile" : "Edit Profile"),
            subtitle: L10n.string("Describe who interacts with this product."),
            symbol: profile == nil ? "person.badge.plus" : "person.crop.circle",
            isValid: isValid,
            actionTitle: L10n.string(profile == nil ? "Add Profile" : "Save Changes"),
            cancel: { dismiss() },
            submit: create
        ) {
            Form {
                TextField(
                    L10n.string("Profile name"),
                    text: $name,
                    prompt: Text(L10n.string("Project Manager"))
                )
                    .textFieldStyle(.roundedBorder)
                    .focused($nameIsFocused)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.string("Short description"))
                    MultilineTextArea(
                        prompt: L10n.string("Plans and coordinates product work"),
                        text: $role,
                        height: 92
                    )
                }
            }
            .formStyle(.grouped)
        }
        .onAppear { nameIsFocused = true }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func create() {
        guard isValid else { return }
        onSave(name, role)
        dismiss()
    }
}

struct NewStorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var actorID: UUID?
    @State private var want: String
    @State private var outcome: String
    @State private var criteria: [AcceptanceCriterion]
    @FocusState private var titleIsFocused: Bool

    let actors: [ProjectActor]
    let story: UserStory?
    let onSave: (String, UUID, String, String, [AcceptanceCriterion]) -> Void

    init(
        actors: [ProjectActor],
        story: UserStory? = nil,
        onSave: @escaping (String, UUID, String, String, [AcceptanceCriterion]) -> Void
    ) {
        self.actors = actors
        self.story = story
        self.onSave = onSave
        _title = State(initialValue: story?.title ?? "")
        _actorID = State(initialValue: story?.actorID ?? actors.first?.id)
        _want = State(initialValue: story?.want ?? "")
        _outcome = State(initialValue: story?.outcome ?? "")
        _criteria = State(
            initialValue: story?.acceptanceCriteria ?? [AcceptanceCriterion(text: "")]
        )
    }

    var body: some View {
        CreationSheetLayout(
            title: L10n.string(story == nil ? "New Story" : "Edit Story"),
            subtitle: L10n.string(
                story == nil
                    ? "Capture the need in a few clear sentences."
                    : "Update the story and its acceptance criteria."
            ),
            symbol: "square.and.pencil",
            isValid: isValid,
            actionTitle: L10n.string(story == nil ? "Create Story" : "Save Changes"),
            cancel: { dismiss() },
            submit: save
        ) {
            Form {
                TextField(
                    L10n.string("Story title"),
                    text: $title,
                    prompt: Text(L10n.string("Create a project"))
                )
                    .textFieldStyle(.roundedBorder)
                    .focused($titleIsFocused)

                Picker(L10n.string("Actor"), selection: $actorID) {
                    Text(L10n.string("Choose an actor")).tag(UUID?.none)
                    ForEach(actors) { actor in
                        Text(actor.name).tag(UUID?.some(actor.id))
                    }
                }

                Section(L10n.string("Story")) {
                    StoryFieldRow(
                        label: L10n.string("I want"),
                        prompt: L10n.string("What is needed?"),
                        text: $want
                    )

                    StoryFieldRow(
                        label: L10n.string("So that"),
                        prompt: L10n.string("Why does it matter?"),
                        text: $outcome
                    )
                }

                Section(L10n.string("Acceptance Criteria")) {
                    ForEach(criteria.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 8) {
                            MultilineTextArea(
                                prompt: L10n.string("Expected result"),
                                text: $criteria[index].text,
                                height: 68
                            )

                            if criteria.count > 1 {
                                Button {
                                    criteria.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .accessibilityLabel(L10n.string("Remove criterion"))
                            }
                        }
                    }

                    Button {
                        criteria.append(AcceptanceCriterion(text: ""))
                    } label: {
                        Label(L10n.string("Add Criterion"), systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                }
            }
            .formStyle(.grouped)
        }
        .onAppear {
            titleIsFocused = true
        }
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            actorID != nil &&
            !want.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !outcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !validCriteria.isEmpty
    }

    private var validCriteria: [AcceptanceCriterion] {
        criteria.compactMap { criterion in
            let text = criterion.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return AcceptanceCriterion(id: criterion.id, text: text, isMet: criterion.isMet)
        }
    }

    private func save() {
        guard isValid, let actorID else { return }
        onSave(title, actorID, want, outcome, validCriteria)
        dismiss()
    }
}

private struct StoryFieldRow: View {
    let label: String
    let prompt: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
            MultilineTextArea(prompt: prompt, text: $text)
                .accessibilityLabel("\(label): \(prompt)")
        }
    }
}

private struct CreationSheetLayout<Content: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    let isValid: Bool
    let actionTitle: String
    let cancel: () -> Void
    let submit: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.title2.weight(.semibold))

                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 28)
            .padding(.horizontal, 28)

            content
                .padding(.horizontal, 12)
                .padding(.vertical, 16)

            Divider()

            HStack {
                Button(L10n.string("Cancel"), action: cancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(actionTitle, action: submit)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding(20)
        }
        .frame(width: 480)
    }
}
