//
//  TemplateUpdateSheet.swift
//  PackingHelper
//
//  End-of-trip review: save items added to template lists back into their templates, and save
//  lists made on the trip as new templates. Existing templates are paged by packer (template
//  owner); new templates show once, on the last page.
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

/// End-of-trip review, in two clearly separate blocks: items added to lists that came from a
/// template (saved back into that template), and lists made on the trip (saved as new templates).
struct TemplateUpdateSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let trip: Trip
    var onSaved: (() -> Void)? = nil

    @Query(sort: \User.created) private var users: [User]
    @Query(filter: #Predicate<PackingList> { $0.template }) private var templates: [PackingList]

    @State private var featureFlags = FeatureFlags.shared
    @State private var pages: [TemplateReviewPage] = []
    @State private var newTemplateLists: [PackingList] = []
    @State private var path: [Int] = []
    @State private var selection: Set<CandidateSelection> = []
    @State private var newTemplateSelection: Set<PersistentIdentifier> = []
    @State private var saveCount = 0

    private var hasSelection: Bool {
        !selection.isEmpty || !newTemplateSelection.isEmpty
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if pages.isEmpty {
                    ContentUnavailableView(
                        "Templates Are Up to Date",
                        systemImage: "checkmark.circle",
                        description: Text("Every item on this trip is already in a template.")
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { dismiss() }
                        }
                    }
                } else {
                    pageView(pages[0], index: 0)
                }
            }
            .navigationDestination(for: Int.self) { index in
                pageView(pages[index], index: index)
            }
        }
        .sensoryFeedback(.success, trigger: saveCount)
        .onAppear {
            // Snapshot candidates so the lists don't shift while reviewing; save re-validates
            guard pages.isEmpty else { return }
            newTemplateLists = trip.newTemplateCandidateLists
            pages = TemplateReviewPage.pages(for: trip.templateCandidateSections)
            // Only new lists: one page that holds just the new templates block
            if pages.isEmpty && !newTemplateLists.isEmpty {
                pages = [TemplateReviewPage(packer: nil, sections: [])]
            }
        }
    }

    // MARK: Page

    private func pageView(_ page: TemplateReviewPage, index: Int) -> some View {
        let isLastPage = index == pages.count - 1

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !page.sections.isEmpty {
                    updateBlock(page)
                }
                // Once, on the last page (pages split existing templates by packer)
                if isLastPage && !newTemplateLists.isEmpty {
                    newTemplatesBlock
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaBar(edge: .bottom) {
            if isLastPage {
                // Pinned so it stays visible however long the page is
                Text(footer(updatesTemplates: pages.contains { !$0.sections.isEmpty }))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
        }
        .navigationTitle(pages.count > 1 ? "\(index + 1) of \(pages.count)" : "Review Trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isLastPage {
                    Button(hasSelection ? "Save" : "Skip", action: save)
                        .fontWeight(.semibold)
                } else {
                    Button("Next") { path.append(index + 1) }
                }
            }
            if !page.sections.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    selectAllButton(for: page)
                }
            }
        }
    }

    private func footer(updatesTemplates: Bool) -> String {
        var sentences: [String] = []
        if updatesTemplates {
            sentences.append("Selected items are added to their templates with a count of 1.")
        }
        if !newTemplateLists.isEmpty {
            sentences.append("New templates keep each item's count.")
        }
        sentences.append("Your other trips won't change.")
        return sentences.joined(separator: " ")
    }

    // MARK: Update Existing Templates

    private func updateBlock(_ page: TemplateReviewPage) -> some View {
        // With a single packer, their name adds nothing
        let packerName = featureFlags.showingMultiplePackers ? page.packer?.name : nil

        return VStack(alignment: .leading, spacing: 12) {
            blockHeader(
                title: packerName.map { "Update \($0)'s Templates" } ?? "Update Your Templates",
                detail: "Items you added on this trip. Selected ones go back into their template.",
                systemImage: "arrow.triangle.2.circlepath",
                tint: .accentColor
            )

            ForEach(page.sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.templateName)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)

                    rowGroup {
                        ForEach(section.candidates) { candidate in
                            candidateRow(candidate, in: section)
                        }
                    }
                }
            }
        }
        .groupedCard()
    }

    private func candidateRow(_ candidate: TemplateCandidate, in section: TemplateReviewSection) -> some View {
        let id = CandidateSelection(list: section.id, key: candidate.key)
        let isSelected = selection.contains(id)

        return selectableRow(isSelected: isSelected, tint: .accentColor) {
            if isSelected {
                selection.remove(id)
            } else {
                selection.insert(id)
            }
        } label: {
            Text(candidate.displayItem.name)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if !candidate.displayItem.category.isEmpty {
                Text(candidate.displayItem.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Save New Templates

    /// Set apart with green (creating something) and an outline, so it doesn't read as more of the above
    private var newTemplatesBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            blockHeader(
                title: "Save New Templates",
                detail: "Lists you made on this trip. Saved ones become templates you can apply to future trips.",
                systemImage: "plus.square.on.square",
                tint: .green
            )

            rowGroup {
                ForEach(newTemplateLists) { list in
                    newTemplateRow(list)
                }
            }
        }
        .groupedCard()
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.green.opacity(0.5), lineWidth: 1)
        }
    }

    private func newTemplateRow(_ list: PackingList) -> some View {
        let id = list.persistentModelID
        let isSelected = newTemplateSelection.contains(id)
        let itemCount = list.items?.count ?? 0
        let nameTaken = PackingList.templateNameExists(list.name, in: templates)

        return selectableRow(isSelected: isSelected, tint: .green) {
            if isSelected {
                newTemplateSelection.remove(id)
            } else {
                newTemplateSelection.insert(id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                ListNameLabel(list: list)
                    .foregroundStyle(.primary)
                Group {
                    if nameTaken {
                        Text("^[\(itemCount) item](inflect: true) · You already have a template named \(list.name)")
                            .foregroundStyle(.orange)
                    } else {
                        Text("^[\(itemCount) item](inflect: true)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Shared Pieces

    private func blockHeader(title: String, detail: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.18), in: .rect(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Rows in one rounded group with separators, like a list section
    private func rowGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Group(subviews: content()) { subviews in
                ForEach(Array(subviews.enumerated()), id: \.offset) { index, subview in
                    subview
                    if index < subviews.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
        .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 10))
    }

    private func selectableRow<Label: View>(
        isSelected: Bool,
        tint: Color,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? tint : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                label()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
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

        return Button(allSelected ? "Deselect All Items" : "Select All Items") {
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
        // Re-checked so a list that was linked meanwhile isn't saved twice
        for list in newTemplateLists
        where newTemplateSelection.contains(list.persistentModelID) && list.isNewTemplateCandidate {
            list.saveAsNewTemplate(named: list.name, owner: users.first, in: modelContext)
        }
        try? modelContext.save()

        if hasSelection {
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.title3)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 8) {
                Text("This trip has \(trip.templateReviewSummary) to review for your templates.")
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
