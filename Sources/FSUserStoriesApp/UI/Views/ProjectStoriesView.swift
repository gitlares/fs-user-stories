// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

struct ProjectStoriesView: View {
    let project: FSProject
    @Binding var selectedStoryID: UUID?
    @State private var searchText = ""
    @State private var selectedActorID: UUID?
    @State private var activeStoriesAreExpanded = true
    @State private var draftStoriesAreExpanded = false
    @State private var completedStoriesAreExpanded = false
    @State private var storyPendingDeletion: UserStory?
    @AppStorage("storySortOrder") private var sortOrderRawValue = StorySortOrder.newest.rawValue
    @FocusState private var storiesListIsFocused: Bool
    let addActor: () -> Void
    let addStory: () -> Void
    let editStory: (UUID) -> Void
    let duplicateStory: (UUID) -> Void
    let deleteStory: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            projectHeader

            if project.actors.isEmpty {
                ContentUnavailableView {
                    Label(L10n.string("No Profiles Yet"), systemImage: "person.2")
                } description: {
                    Text(L10n.string("Add the people or roles who will use this product."))
                } actions: {
                    Button(L10n.string("Add Profile"), action: addActor)
                        .buttonStyle(.glass)
                }
            } else if project.stories.isEmpty {
                ContentUnavailableView {
                    Label(L10n.string("No Stories Yet"), systemImage: "text.page")
                } description: {
                    Text(L10n.string("Create the first user story for this project."))
                } actions: {
                    Button(L10n.string("Add Story"), action: addStory)
                        .buttonStyle(.glass)
                }
            } else if filteredStories.isEmpty {
                ContentUnavailableView {
                    Label(L10n.string("No Matching Stories"), systemImage: "magnifyingglass")
                } description: {
                    Text(L10n.string("Try a different title, actor, description, or criterion."))
                }
            } else {
                ScrollViewReader { proxy in
                    List {
                        storySection(
                            title: L10n.string("Active Stories"),
                            stories: stories(with: .active),
                            isExpanded: $activeStoriesAreExpanded
                        )
                        storySection(
                            title: L10n.string("Draft Stories"),
                            stories: stories(with: .draft),
                            isExpanded: $draftStoriesAreExpanded
                        )
                        storySection(
                            title: L10n.string("Completed Stories"),
                            stories: stories(with: .done),
                            isExpanded: $completedStoriesAreExpanded
                        )
                    }
                    .listStyle(.inset)
                    .focusable()
                    .focused($storiesListIsFocused)
                    .focusEffectDisabled()
                    .onMoveCommand(perform: moveSelection)
                    .onChange(of: selectedStoryID) {
                        guard let selectedStoryID else { return }
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(selectedStoryID, anchor: .center)
                        }
                    }
                }
            }
        }
        .onChange(of: searchText) {
            let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            activeStoriesAreExpanded = true
            draftStoriesAreExpanded = isSearching
            completedStoriesAreExpanded = isSearching
        }
        .alert(
            L10n.string("Delete Story?"),
            isPresented: deleteConfirmationIsPresented,
            presenting: storyPendingDeletion
        ) { story in
            Button(L10n.string("Delete Story"), role: .destructive) {
                deleteStory(story.id)
                storyPendingDeletion = nil
            }
            Button(L10n.string("Cancel"), role: .cancel) {
                storyPendingDeletion = nil
            }
        } message: { _ in
            Text(
                L10n.string(
                    "Deleting this story will permanently remove it, its acceptance criteria, and its attachments. This cannot be undone."
                )
            )
        }
        .navigationSplitViewColumnWidth(min: 320, ideal: 390, max: 480)
    }

    private var deleteConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { storyPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    storyPendingDeletion = nil
                }
            }
        )
    }

    private var filteredStories: [UserStory] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return project.stories.filter { story in
            guard selectedActorID == nil || story.actorID == selectedActorID else {
                return false
            }
            guard !query.isEmpty else { return true }

            let actor = project.actors.first { $0.id == story.actorID }
            let searchableText = [
                "\(project.prefix)-\(story.number)",
                story.title,
                story.want,
                story.outcome,
                story.notes,
                actor?.name ?? "",
                actor?.role ?? "",
                story.acceptanceCriteria.map(\.text).joined(separator: " ")
            ].joined(separator: " ")

            return searchableText.localizedStandardContains(query)
        }.sorted(by: sortOrder.areInIncreasingOrder)
    }

    private func stories(with status: StoryStatus) -> [UserStory] {
        filteredStories.filter { $0.status == status }
    }

    @ViewBuilder
    private func storySection(
        title: String,
        stories: [UserStory],
        isExpanded: Binding<Bool>
    ) -> some View {
        if !stories.isEmpty || searchText.isEmpty {
            Section {
                if isExpanded.wrappedValue {
                    if stories.isEmpty {
                        Text(L10n.string("No stories in this section"))
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(stories) { story in
                            Button {
                                selectedStoryID = story.id
                                storiesListIsFocused = true
                            } label: {
                                StoryRow(
                                    story: story,
                                    reference: "\(project.prefix)-\(story.number)",
                                    actor: project.actors.first { $0.id == story.actorID }
                                )
                                .padding(.horizontal, 10)
                                .background {
                                    if selectedStoryID == story.id {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(selectionColor)
                                    }
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .id(story.id)
                            .contextMenu {
                                Button {
                                    editStory(story.id)
                                } label: {
                                    Label(L10n.string("Edit Story"), systemImage: "pencil")
                                }
                                .disabled(story.status == .done)

                                Button {
                                    duplicateStory(story.id)
                                } label: {
                                    Label(L10n.string("Duplicate Story"), systemImage: "plus.square.on.square")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    storyPendingDeletion = story
                                } label: {
                                    Label(L10n.string("Delete Story"), systemImage: "trash")
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                }
            } header: {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded.wrappedValue.toggle()
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                            .foregroundStyle(.secondary)

                        Text(title)

                        Spacer()

                        Text("\(stories.count)")
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityValue(
                    isExpanded.wrappedValue
                        ? L10n.string("Expanded")
                        : L10n.string("Collapsed")
                )
            }
        }
    }

    private var selectionColor: Color {
        Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    }

    private var visibleStories: [UserStory] {
        var result: [UserStory] = []
        if activeStoriesAreExpanded { result.append(contentsOf: stories(with: .active)) }
        if draftStoriesAreExpanded { result.append(contentsOf: stories(with: .draft)) }
        if completedStoriesAreExpanded { result.append(contentsOf: stories(with: .done)) }
        return result
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !visibleStories.isEmpty else { return }

        let currentIndex = selectedStoryID.flatMap { selectedID in
            visibleStories.firstIndex { $0.id == selectedID }
        }

        switch direction {
        case .down:
            let nextIndex = min((currentIndex ?? -1) + 1, visibleStories.count - 1)
            selectedStoryID = visibleStories[nextIndex].id
        case .up:
            let previousIndex = max((currentIndex ?? visibleStories.count) - 1, 0)
            selectedStoryID = visibleStories[previousIndex].id
        default:
            return
        }
    }

    private var projectHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.string("Stories"))
                    .font(.title2.weight(.semibold))

                Spacer()

                Text("\(project.stories.count)")
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            TextField(L10n.string("Search stories"), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)

            HStack(spacing: 10) {
                if !project.actors.isEmpty {
                    Label(L10n.string("Profile"), systemImage: "line.3.horizontal.decrease")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)

                    Picker(L10n.string("Filter by Profile"), selection: $selectedActorID) {
                        Text(L10n.string("All Profiles"))
                            .tag(UUID?.none)

                        Divider()

                        ForEach(project.actors) { actor in
                            Text(actor.name)
                                .tag(UUID?.some(actor.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()

                Picker(L10n.string("Sort Stories"), selection: sortOrderBinding) {
                    ForEach(StorySortOrder.allCases) { order in
                        Text(order.localizedName).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .help(L10n.string("Sort Stories"))
                .accessibilityLabel(L10n.string("Sort Stories"))
            }
        }
        .padding(20)
    }

    private var sortOrder: StorySortOrder {
        StorySortOrder(rawValue: sortOrderRawValue) ?? .newest
    }

    private var sortOrderBinding: Binding<StorySortOrder> {
        Binding(
            get: { sortOrder },
            set: { sortOrderRawValue = $0.rawValue }
        )
    }
}

private enum StorySortOrder: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case title

    var id: Self { self }

    var localizedName: String {
        switch self {
        case .newest: L10n.string("Newest First")
        case .oldest: L10n.string("Oldest First")
        case .title: L10n.string("Title A–Z")
        }
    }

    func areInIncreasingOrder(_ lhs: UserStory, _ rhs: UserStory) -> Bool {
        switch self {
        case .newest:
            lhs.createdAt == rhs.createdAt ? lhs.number > rhs.number : lhs.createdAt > rhs.createdAt
        case .oldest:
            lhs.createdAt == rhs.createdAt ? lhs.number < rhs.number : lhs.createdAt < rhs.createdAt
        case .title:
            switch lhs.title.localizedStandardCompare(rhs.title) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: lhs.number < rhs.number
            }
        }
    }
}

private struct StoryRow: View {
    let story: UserStory
    let reference: String
    let actor: ProjectActor?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(reference)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(story.status.localizedName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(story.title)
                .font(.headline)
                .lineLimit(2)

            if let actor {
                HStack {
                    Label(actor.name, systemImage: "person")

                    Spacer()

                    if !story.acceptanceCriteria.isEmpty {
                        Text(
                            L10n.criterionProgress(
                                met: story.metCriteriaCount,
                                total: story.acceptanceCriteria.count
                            )
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !story.acceptanceCriteria.isEmpty {
                ProgressView(value: story.criteriaProgress)
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}
