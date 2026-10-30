//
//  PackingListApplyDefaultView.swift
//  PackingHelper
//
//  Created by Todd Louison on 11/14/23.
//
//  One screen: tap templates to select them, then Apply. Templates are grouped by list type
//  and sorted by name; ones already on the trip show at the end and can't be picked again.
//

import SwiftData
import SwiftUI

struct PackingListApplyDefaultView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let trip: Trip

    @Query(filter: #Predicate<PackingList> { $0.template == true }, animation: .snappy)
    private var templates: [PackingList]

    @State private var selectedUser: User?
    @State private var selectedLists: [PackingList] = []
    @State private var searchText = ""
    @State private var featureFlags = FeatureFlags.shared

    /// Search only shows once there are enough templates to need it
    private static let searchThreshold = 8

    private var appliedTemplates: [PackingList] {
        trip.alreadyUsedTemplates
    }

    private var availableTemplates: [PackingList] {
        let applied = appliedTemplates
        return templates.filter { list in
            !applied.contains(list) &&
            (searchText.isEmpty || list.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    /// Everyday packing, tasks, then day-of packing and day-of tasks (the order they sit on a
    /// trip); each sorted by name. Empty groups are dropped.
    private var templateGroups: [TemplateGroup] {
        let available = availableTemplates
        return [false, true].flatMap { isDayOf in
            ListKind.allCases.compactMap { kind in
                let lists = available
                    .filter { $0.kind == kind && $0.isDayOf == isDayOf }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                return lists.isEmpty ? nil : TemplateGroup(kind: kind, isDayOf: isDayOf, lists: lists)
            }
        }
    }

    private var confirmTitle: String {
        selectedLists.count > 1 ? "Apply \(selectedLists.count)" : "Apply"
    }

    var body: some View {
        NavigationStack {
            content
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Apply Templates")
                .navigationBarTitleDisplayMode(.inline)
                .editSheetToolbar(confirmTitle: confirmTitle, canConfirm: !selectedLists.isEmpty) {
                    trip.applyDefaultLists(to: selectedUser, lists: selectedLists, in: modelContext)
                    dismiss()
                }
                .modifier(TemplateSearch(isEnabled: templates.count >= Self.searchThreshold, text: $searchText))
        }
    }

    @ViewBuilder
    private var content: some View {
        if templates.isEmpty {
            PackingListEmptyStateView(
                hasFilters: false,
                message: "No templates to apply yet. Make one in the Templates tab, or save a trip's list as a template.",
                actionButtonTitle: "Done",
                onAction: { dismiss() }
            )
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if featureFlags.showingMultiplePackers {
                        packerSection
                    }

                    let groups = templateGroups
                    if groups.isEmpty {
                        Text(searchText.isEmpty ? "Every template is already on this trip." : "No templates match \"\(searchText)\".")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                // A lone group needs no header
                                if groups.count > 1 {
                                    sectionHeader(group.title)
                                }

                                ForEach(group.lists) { list in
                                    SelectablePackingListCard(
                                        list: list,
                                        isSelected: selectedLists.contains(list),
                                        showsOwner: featureFlags.showingMultiplePackers
                                    ) {
                                        toggleSelection(for: list)
                                    }
                                }
                            }
                        }
                    }

                    if !appliedTemplates.isEmpty && searchText.isEmpty {
                        appliedSection
                    }
                }
                .padding()
            }
            .sensoryFeedback(.selection, trigger: selectedLists.count)
        }
    }

    private var packerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            UserPickerView(selectedUser: $selectedUser, style: .inline)
                .padding(.vertical, 10)
                .padding(.horizontal)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 12))

            Text(selectedUser == nil ?
                 "Each template's items go to the packer who owns it." :
                    "Templates without an owner go to \(selectedUser?.name ?? ""). Owned templates always go to their owner.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
    }

    private var appliedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Already on This Trip")

            // One inset gray panel, not cards, so these read as done rather than pickable
            let applied = appliedTemplates.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            VStack(spacing: 0) {
                ForEach(applied) { list in
                    HStack {
                        ListNameLabel(list: list)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
                    .padding(.horizontal)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Already on this trip")

                    if list != applied.last {
                        Divider()
                            .padding(.leading)
                    }
                }
            }
            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal)
            .accessibilityAddTraits(.isHeader)
    }

    private func toggleSelection(for list: PackingList) {
        withAnimation(.snappy) {
            if let index = selectedLists.firstIndex(of: list) {
                selectedLists.remove(at: index)
            } else {
                selectedLists.append(list)
            }
        }
    }
}

private struct TemplateGroup: Identifiable {
    let kind: ListKind
    let isDayOf: Bool
    let lists: [PackingList]

    var id: String { "\(kind.rawValue)-\(isDayOf)" }

    /// "Packing", "Tasks", "Day Of", "Day Of Tasks"
    var title: String { kind.displayName(isDayOf: isDayOf) }
}

/// `.searchable` only when there are enough templates to need it
private struct TemplateSearch: ViewModifier {
    let isEnabled: Bool
    @Binding var text: String

    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(text: $text, prompt: "Search Templates")
        } else {
            content
        }
    }
}

// MARK: - Supporting Views

struct SelectablePackingListCard: View {
    let list: PackingList
    let isSelected: Bool
    var showsOwner: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Left side: Name and selection indicator
                HStack(spacing: 8) {
                    ListNameLabel(list: list)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }

                Spacer()

                // Right side: Owner, count and type icon
                HStack(spacing: 8) {
                    if showsOwner, let owner = list.user {
                        owner.pillIcon
                    }

                    HStack(spacing: 4) {
                        Text("\(list.totalItems)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        list.iconImage
                            .foregroundStyle(Color.accentColor)
                            .font(.subheadline)
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
