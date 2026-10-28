//
//  AISuggestedItemList.swift
//  PackingHelper
//
//  Renders an assistant reply's suggested items as a list grouped into
//  category sections, each with its own "Add all" affordance. Tapping a row
//  adds to the automatic destination (the list the assistant picked, or the
//  Default list, made if missing), which the row names when the trip has
//  multiple lists or the list would be new;
//  long-press (row) or the Add all menu picks another.
//

import SwiftUI

/// The list a suggestion goes to when tapped, possibly one that tapping creates
struct AISuggestionDestination {
    let name: String
    let kind: ListKind
    let isDayOf: Bool
    /// The trip has no such list yet; tapping makes it (Default or Tasks)
    let isNew: Bool
}

struct AISuggestedItemList: View {
    let suggestions: [AISuggestedItem]
    let lists: [PackingList]
    let isAdded: (AISuggestedItem) -> Bool
    /// The automatic destination, shown when there's more than one list to choose from
    let destination: (AISuggestedItem) -> AISuggestionDestination?
    /// `nil` list = automatic destination.
    let onAdd: (AISuggestedItem, PackingList?) -> Void
    /// Adds every not-yet-added item in one section.
    let onAddAll: ([AISuggestedItem], PackingList?) -> Void

    /// Display order for sections; tasks last since they aren't packed.
    private static let sectionOrder: [PackingRecommendationCategory] = [
        .Clothing, .Toiletries, .Electronics, .other, .Task
    ]

    private struct CategorySection: Identifiable {
        let category: PackingRecommendationCategory
        let items: [AISuggestedItem]
        var id: PackingRecommendationCategory { category }
    }

    private var sections: [CategorySection] {
        let grouped = Dictionary(grouping: suggestions) { $0.category }
        return Self.sectionOrder.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return CategorySection(category: category, items: items)
        }
    }

    var body: some View {
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(sections) { section in
                    sectionView(section.category, items: section.items)
                }
            }
        }
    }

    // MARK: - Section

    private func sectionView(_ category: PackingRecommendationCategory, items: [AISuggestedItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: categoryIcon(category))
                Text(categoryTitle(category))
                Text("\(items.count)")
                    .foregroundStyle(.tertiary)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, suggestion in
                    row(for: suggestion)
                    if index < items.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if items.count > 1 {
                addAllButton(for: items)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(for suggestion: AISuggestedItem) -> some View {
        let added = isAdded(suggestion)
        Button {
            withAnimation(.packingSpring) { onAdd(suggestion, nil) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: added ? "checkmark" : categoryIcon(suggestion.category))
                    .font(.subheadline.weight(.medium))
                    .frame(width: 28, height: 28)
                    .background(added ? Color.green.opacity(0.15) : Color.accentColor.opacity(0.12))
                    .foregroundStyle(added ? Color.green : Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(suggestion.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(added ? .secondary : .primary)
                    detailLine(for: suggestion, added: added)
                }

                Spacer(minLength: 8)

                if suggestion.count > 1 {
                    Text("×\(suggestion.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(added ? Color.green : Color.accentColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(added)
        .contextMenu {
            if lists.count > 1 && !added {
                listButtons { list in
                    withAnimation(.packingSpring) { onAdd(suggestion, list) }
                }
            }
        }
        .accessibilityLabel(accessibilityLabel(for: suggestion, added: added))
    }

    /// "for Laptop, packed on Maui · Beach". The list is left off once added, since
    /// "Add to" may have put it somewhere else
    @ViewBuilder
    private func detailLine(for suggestion: AISuggestedItem, added: Bool) -> some View {
        let detail = detail(for: suggestion)
        let destination = added ? nil : shownDestination(for: suggestion)
        if detail != nil || destination != nil {
            HStack(spacing: 4) {
                if let detail {
                    Text(detail)
                }
                if detail != nil, destination != nil {
                    Text("·")
                }
                if let destination {
                    HStack(spacing: 4) {
                        if destination.isNew {
                            Text("New list:")
                        }
                        ListNameLabel(name: destination.name, kind: destination.kind, isDayOf: destination.isDayOf)
                    }
                    .layoutPriority(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    /// Named when there's a choice of lists, or when tapping would create one
    private func shownDestination(for suggestion: AISuggestedItem) -> AISuggestionDestination? {
        guard let destination = destination(suggestion) else { return nil }
        return lists.count > 1 || destination.isNew ? destination : nil
    }

    // MARK: - Add all

    @ViewBuilder
    private func addAllButton(for items: [AISuggestedItem]) -> some View {
        let allAdded = items.allSatisfy { isAdded($0) }
        let label = Label(allAdded ? "All added" : "Add all", systemImage: allAdded ? "checkmark.circle.fill" : "plus.circle")
            .font(.footnote.weight(.medium))

        if lists.count > 1 {
            Menu {
                listButtons { onAddAll(items, $0) }
            } label: {
                label
            } primaryAction: {
                onAddAll(items, nil)
            }
            .disabled(allAdded)
        } else {
            Button { onAddAll(items, nil) } label: { label }
                .disabled(allAdded)
        }
    }

    private func listButtons(_ action: @escaping (PackingList) -> Void) -> some View {
        Section("Add to") {
            ForEach(lists, id: \.id) { list in
                Button { action(list) } label: { ListMenuLabel(list: list) }
            }
        }
    }

    // MARK: - Helpers

    /// "for Laptop" and/or "packed on Maui"
    private func detail(for suggestion: AISuggestedItem) -> String? {
        var parts: [String] = []
        if let accessoryFor = suggestion.accessoryFor, !accessoryFor.isEmpty { parts.append("for \(accessoryFor)") }
        if let fromTrip = suggestion.fromTrip, !fromTrip.isEmpty { parts.append("packed on \(fromTrip)") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func accessibilityLabel(for suggestion: AISuggestedItem, added: Bool) -> String {
        var parts = [suggestion.name]
        if suggestion.count > 1 { parts.append("quantity \(suggestion.count)") }
        if let detail = detail(for: suggestion) { parts.append(detail) }
        if !added, let destination = shownDestination(for: suggestion) {
            parts.append(destination.isNew ? "adds to a new \(destination.name) list" : "adds to \(destination.name)")
        }
        parts.append(added ? "added" : "tap to add")
        return parts.joined(separator: ", ")
    }

    private func categoryTitle(_ category: PackingRecommendationCategory) -> String {
        switch category {
        case .Clothing: return "Clothing"
        case .Electronics: return "Electronics"
        case .Toiletries: return "Toiletries"
        case .Task: return "Tasks"
        case .other: return "Other"
        }
    }

    private func categoryIcon(_ category: PackingRecommendationCategory) -> String {
        switch category {
        case .Clothing: return "tshirt"
        case .Electronics: return "bolt"
        case .Toiletries: return "drop"
        case .Task: return "checklist"
        case .other: return "shippingbox"
        }
    }
}
