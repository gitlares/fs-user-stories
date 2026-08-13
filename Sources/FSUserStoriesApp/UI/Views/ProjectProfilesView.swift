// SPDX-License-Identifier: MIT

import SwiftUI

struct ProjectProfilesView: View {
    let project: FSProject
    @Binding var selectedProfileID: UUID?
    let addProfile: () -> Void
    let editProfile: (UUID) -> Void
    let deleteProfile: (UUID) -> Void

    @State private var searchText = ""
    @State private var profilePendingDeletion: ProjectActor?

    var body: some View {
        VStack(spacing: 0) {
            header

            if project.actors.isEmpty {
                ContentUnavailableView {
                    Label(L10n.string("No Profiles Yet"), systemImage: "person.2")
                } description: {
                    Text(L10n.string("Add the people or roles who interact with this product."))
                } actions: {
                    Button(L10n.string("Add Profile"), action: addProfile)
                        .buttonStyle(.glass)
                }
            } else if filteredProfiles.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(filteredProfiles, selection: $selectedProfileID) { profile in
                    profileRow(profile)
                        .tag(profile.id)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            profileActions(profile)
                        }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $searchText, prompt: Text(L10n.string("Search profiles")))
        .onAppear {
            if selectedProfileID == nil {
                selectedProfileID = project.actors.first?.id
            }
        }
        .alert(
            L10n.string("Delete Profile?"),
            isPresented: deleteConfirmationIsPresented,
            presenting: profilePendingDeletion
        ) { profile in
            Button(L10n.string("Delete Profile"), role: .destructive) {
                deleteProfile(profile.id)
                profilePendingDeletion = nil
            }
            Button(L10n.string("Cancel"), role: .cancel) {
                profilePendingDeletion = nil
            }
        } message: { _ in
            Text(L10n.string("Deleting this profile is permanent and cannot be undone."))
        }
        .navigationSplitViewColumnWidth(min: 320, ideal: 390, max: 480)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("Profiles"))
                    .font(.title2.weight(.semibold))
                Text(L10n.string("People and roles represented in this project."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(project.actors.count)")
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())

            Button(action: addProfile) {
                Image(systemName: "plus")
            }
            .buttonStyle(.glass)
            .help(L10n.string("Add Profile"))
        }
        .padding(20)
        .background(.background)
    }

    private var filteredProfiles: [ProjectActor] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return project.actors }
        return project.actors.filter {
            $0.name.localizedStandardContains(query) ||
                $0.role.localizedStandardContains(query)
        }
    }

    private func storyCount(for profile: ProjectActor) -> Int {
        project.stories.lazy.filter { $0.actorID == profile.id }.count
    }

    private func profileRow(_ profile: ProjectActor) -> some View {
        let usageCount = storyCount(for: profile)

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 5) {
                Text(profile.name)
                    .font(.headline)
                    .lineLimit(1)

                if !profile.role.isEmpty {
                    Text(profile.role)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Text(L10n.storyCount(usageCount))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Menu {
                profileActions(profile)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityAction(named: L10n.string("Edit Profile")) {
            editProfile(profile.id)
        }
    }

    @ViewBuilder
    private func profileActions(_ profile: ProjectActor) -> some View {
        Button {
            editProfile(profile.id)
        } label: {
            Label(L10n.string("Edit Profile"), systemImage: "pencil")
        }

        Divider()

        Button(role: .destructive) {
            profilePendingDeletion = profile
        } label: {
            Label(L10n.string("Delete Profile"), systemImage: "trash")
        }
        .disabled(storyCount(for: profile) > 0)

        if storyCount(for: profile) > 0 {
            Text(L10n.string("A profile used by stories cannot be deleted."))
        }
    }

    private var deleteConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { profilePendingDeletion != nil },
            set: { isPresented in
                if !isPresented { profilePendingDeletion = nil }
            }
        )
    }
}

struct ProfileDetailView: View {
    let profile: ProjectActor
    let project: FSProject
    let editProfile: () -> Void
    let deleteProfile: () -> Void

    @State private var deleteConfirmationIsPresented = false

    private var stories: [UserStory] {
        project.stories.filter { $0.actorID == profile.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(.tint)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(profile.name)
                            .font(.largeTitle.weight(.semibold))
                            .textSelection(.enabled)

                        Text(L10n.storyCount(stories.count))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(action: editProfile) {
                        Label(L10n.string("Edit Profile"), systemImage: "pencil")
                    }
                    .buttonStyle(.glass)

                    Menu {
                        Button(L10n.string("Delete Profile"), role: .destructive) {
                            deleteConfirmationIsPresented = true
                        }
                        .disabled(!stories.isEmpty)

                        if !stories.isEmpty {
                            Text(L10n.string("A profile used by stories cannot be deleted."))
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuIndicator(.hidden)
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                GroupBox(L10n.string("Description")) {
                    Text(
                        profile.role.isEmpty
                            ? L10n.string("No description")
                            : profile.role
                    )
                    .foregroundStyle(profile.role.isEmpty ? .tertiary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                }

                GroupBox(L10n.string("Stories")) {
                    if stories.isEmpty {
                        Text(L10n.string("This profile is not used by any stories yet."))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(stories) { story in
                                HStack(spacing: 10) {
                                    Text("\(project.prefix)-\(story.number)")
                                        .font(.caption.monospaced().weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(story.title)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(story.status.localizedName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)

                                if story.id != stories.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(36)
        }
        .alert(L10n.string("Delete Profile?"), isPresented: $deleteConfirmationIsPresented) {
            Button(L10n.string("Delete Profile"), role: .destructive, action: deleteProfile)
            Button(L10n.string("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("Deleting this profile is permanent and cannot be undone."))
        }
    }
}
