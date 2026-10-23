//
//  TemplateUpdateSheet.swift
//  PackingHelper
//
//  Review trip items that aren't in their section's template and save the chosen ones back.
//  Paged by packer (template owner) so each person's templates are reviewed on their own.
//

import SwiftUI
import SwiftData

// MARK: - Review Model

/// One trip section's candidates
struct TemplateReviewSection: Identifiable {
    let list: PackingList
    let candidates: [TemplateCandidate]

    var id: PersistentIdentifier { list.persistentModelID }

    var templateName: String {
        list.appliedFromTemplate?.name ?? list.name
    }
}

/// One packer's page: their templates' candidates. `packer == nil` = templates without an owner.
struct TemplateReviewPage: Identifiable {
    let packer: User?
    let sections: [TemplateReviewSection]

    var id: PersistentIdentifier? { packer?.persistentModelID }

    var title: String {
        if let packer {
            return "\(packer.name)'s Items"
        }
        return "Shared Templates"
    }

    /// Owned pages ordered by packer creation, shared page last
    static func pages(for lists: [PackingList]) -> [TemplateReviewPage] {
        var owners: [User] = []
        var sectionsByOwner: [PersistentIdentifier: [TemplateReviewSection]] = [:]
        var sharedSections: [TemplateReviewSection] = []

        for list in lists {
            let candidates = list.templateCandidates
            guard !candidates.isEmpty else { continue }
            let section = TemplateReviewSection(list: list, candidates: candidates)

            if let owner = list.appliedFromTemplate?.user {
                let ownerID = owner.persistentModelID
                if sectionsByOwner[ownerID] == nil {
                    owners.append(owner)
                }
                sectionsByOwner[ownerID, default: []].append(section)
            } else {
                sharedSections.append(section)
            }
        }

        var pages: [TemplateReviewPage] = owners
            .sorted { $0.created < $1.created }
            .map { owner in
                TemplateReviewPage(packer: owner, sections: sectionsByOwner[owner.persistentModelID] ?? [])
            }
        if !sharedSections.isEmpty {
            pages.append(TemplateReviewPage(packer: nil, sections: sharedSections))
        }
        return pages
    }
}

/// Identifies a candidate within a specific section (the same name can be a candidate in two sections)
private struct CandidateSelection: Hashable {
    let list: PersistentIdentifier
    let key: String
}

// MARK: - Sheet

struct TemplateUpdateSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Trip sections to review (one for the section menu, all candidate sections for the post-trip card)
    let sections: [PackingList]
    var onSaved: (() -> Void)? = nil

    @State private var featureFlags = FeatureFlags.shared
    @State private var pages: [TemplateReviewPage] = []
    @State private var path: [Int] = []
    @State private var selection: Set<CandidateSelection> = []
    @State private var saveCount = 0

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let firstPage = pages.first {
                    pageView(firstPage, index: 0)
                } else {
                    ContentUnavailableView(
                        "Templates Are Up to Date",
                        systemImage: "checkmark.circle",
                        description: Text("Every item on this trip is already in its template.")
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { dismiss() }
                        }
                    }
                }
            }
            .navigationDestination(for: Int.self) { index in
                pageView(pages[index], index: index)
            }
        }
        .sensoryFeedback(.success, trigger: saveCount)
        .onAppear {
            // Snapshot candidates so the list doesn't shift while reviewing; save re-validates
            if pages.isEmpty {
                pages = TemplateReviewPage.pages(for: sections)
            }
        }
    }

    // MARK: Page

    private func pageView(_ page: TemplateReviewPage, index: Int) -> some View {
        let isLastPage = index == pages.count - 1

        return List {
            Section {
                pageHeader(page)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            ForEach(page.sections) { section in
                Section {
                    ForEach(section.candidates) { candidate in
                        candidateRow(candidate, in: section)
                    }
                } header: {
                    Text("\(section.templateName) Template")
                }
            }
        }
        .safeAreaBar(edge: .bottom) {
            if isLastPage {
                // Pinned so it stays visible however long the list is
                Text("Added items start with a count of 1. Trips that already use these templates aren't changed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
        }
        .navigationTitle(pages.count > 1 ? "\(index + 1) of \(pages.count)" : "Update Templates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isLastPage {
                    Button(selection.isEmpty ? "Skip" : "Add \(selection.count) to Templates", action: save)
                        .fontWeight(.semibold)
                } else {
                    Button("Next") { path.append(index + 1) }
                }
            }
            ToolbarItem(placement: .bottomBar) {
                selectAllButton(for: page)
            }
        }
    }

    private func pageHeader(_ page: TemplateReviewPage) -> some View {
        // With a single packer, their name and avatar add nothing
        let showsPacker = featureFlags.showingMultiplePackers

        return HStack(spacing: 12) {
            if let packer = page.packer {
                if showsPacker {
                    // profileView is fixed at 60pt
                    packer.profileView
                        .scaleEffect(2 / 3)
                        .frame(width: 40, height: 40)
                }
            } else {
                Image(systemName: "person.2.circle.fill")
                    .resizable()
                    .frame(width: 40, height: 40)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(page.packer != nil && !showsPacker ? "New Items" : page.title)
                    .font(.headline)
                Text("Choose items to add to these templates for future trips.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func candidateRow(_ candidate: TemplateCandidate, in section: TemplateReviewSection) -> some View {
        let id = CandidateSelection(list: section.id, key: candidate.key)
        let isSelected = selection.contains(id)

        return Button {
            if isSelected {
                selection.remove(id)
            } else {
                selection.insert(id)
            }
        } label: {
            // Single line so the name lines up with the selection circle
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .contentTransition(.symbolEffect(.replace))

                Text(candidate.displayItem.name)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                if !candidate.displayItem.category.isEmpty {
                    Text(candidate.displayItem.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectAllButton(for page: TemplateReviewPage) -> some View {
        let pageIDs = Set(page.sections.flatMap { section in
            section.candidates.map { CandidateSelection(list: section.id, key: $0.key) }
        })
        let allSelected = pageIDs.isSubset(of: selection)

        return Button(allSelected ? "Deselect All" : "Select All") {
            if allSelected {
                selection.subtract(pageIDs)
            } else {
                selection.formUnion(pageIDs)
            }
        }
    }

    // MARK: Save

    private func save() {
        for section in pages.flatMap(\.sections) {
            let chosen = section.candidates.filter {
                selection.contains(CandidateSelection(list: section.id, key: $0.key))
            }
            if !chosen.isEmpty {
                section.list.saveToTemplate(chosen, in: modelContext)
            }
        }
        try? modelContext.save()

        if !selection.isEmpty {
            saveCount += 1
        }
        onSaved?()
        dismiss()
    }
}

// MARK: - Post-Trip Card

/// Shown in trip detail once a trip is complete and it has items that aren't in their templates
struct TemplateReviewCard: View {
    let trip: Trip
    let onReview: () -> Void

    private var itemCount: Int { trip.templateCandidateCount }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.title3)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 8) {
                Text("You added ^[\(itemCount) item](inflect: true) that \(itemCount == 1 ? "isn't" : "aren't") in your templates.")
                    .font(.subheadline)

                Button("Review", action: onReview)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Spacer(minLength: 0)

            Button {
                withAnimation {
                    trip.templateReviewDismissed = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .roundedBox(background: .ultraThick)
        .shaded()
    }
}
