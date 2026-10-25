//
//  TripPackingSheet.swift
//  PackingHelper
//
//  Created by Todd Louison on 10/11/23.
//

import SwiftUI
import SwiftData

/// Packing progress card on trip detail; the whole card opens the packing list.
/// Adding/applying sections lives in the packing list's own toolbar once the trip has lists.
struct TripDetailPackingView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.tripDetailCardFillsHeight) private var fillsHeight
    /// Columns of list rows; 2 when the card spans a wide layout
    @Environment(\.tripDetailPackingColumns) private var columns

    let trip: Trip

    @Binding var isAddingNewPackingList: Bool
    @Binding var isApplyingDefaultPackingList: Bool

    @State private var isShowingTemplateReview = false
    @State private var featureFlags = FeatureFlags.shared

    /// Caps the section breakdown so the card stays a summary (and the no-scroll wide layouts stay on
    /// screen): 4 rows, in as many columns as the card has
    private var sectionLimit: Int { 4 * max(columns, 1) }

    private var sections: [PackingList] {
        PackingList.sorted(trip.lists ?? [], sortOrder: .byCustomOrder)
            .filter { $0.totalItems > 0 }
    }

    private var visibleSections: [PackingList] {
        Array(sections.prefix(sectionLimit))
    }

    /// Unpacked items in packing-list order, shown under the sections when the card has spare height
    private var upNextItems: [Item] {
        sections.flatMap { list in
            (list.items ?? []).filter { !$0.isPacked }.sorted { $0.sortOrder < $1.sortOrder }
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            if (trip.lists ?? []).isEmpty {
                emptyState
                    .frame(maxHeight: fillsHeight ? .infinity : nil)
                    .roundedBox()
                    .shaded()
            } else {
                NavigationLink {
                    PackingListContainerView(
                        trip: trip,
                        users: trip.packers.isEmpty ? nil : trip.packers,
                        title: trip.name
                    )
                } label: {
                    card
                }
                .buttonStyle(.plain)
                .roundedBox()
                .shaded()

                if trip.showsTemplateReviewCard {
                    TemplateReviewCard(trip: trip) {
                        isShowingTemplateReview = true
                    }
                    .transition(.opacity)
                }
            }
        }
        // Owned here (not by the card) so hiding the card after saving doesn't tear down the sheet
        .sheet(isPresented: $isShowingTemplateReview) {
            TemplateUpdateSheet(sections: trip.templateCandidateSections) {
                trip.templateReviewDismissed = true
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing to Pack Yet", systemImage: suitcaseIcon)
        } description: {
            Text("Apply a template or start an empty list.")
        } actions: {
            CreateListMenu(
                isAddingNewPackingList: $isAddingNewPackingList,
                isApplyingDefaultPackingList: $isApplyingDefaultPackingList
            )
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
        }
    }

    private var card: some View {
        let total = trip.totalItemsCount
        let packed = trip.packedItemsCount

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                TripDetailPackingProgressView(
                    val: Double(packed),
                    total: Double(total),
                    image: Image(systemName: suitcaseIcon)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(headline(packed: packed, total: total))
                        .font(.title3.bold())
                        .contentTransition(.numericText())
                    Text(subtitle(packed: packed, total: total))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if featureFlags.showingMultiplePackers && !trip.packers.isEmpty {
                    UserIndicators(users: trip.packers)
                }

                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            if !visibleSections.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    // Filled row by row, so the list order reads left to right
                    ForEach(sectionRows, id: \.first?.persistentModelID) { row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.element.persistentModelID) { index, list in
                                if index > 0 {
                                    // Gutter between columns
                                    Color.clear.frame(width: 12, height: 1)
                                }
                                sectionCells(list)
                            }
                        }
                    }
                }

                if visibleSections.count < sections.count {
                    Text("+\(sections.count - visibleSections.count) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if fillsHeight {
                upNext
            }
        }
        .frame(maxHeight: fillsHeight ? .infinity : nil, alignment: .top)
        .contentShape(.rect)
        .animation(.smooth, value: packed)
    }

    @ViewBuilder
    private var upNext: some View {
        let items = upNextItems
        if !items.isEmpty {
            // Heading rides inside the fitting stack so it disappears when no item row fits under it
            FittingVStack(spacing: 10, requiresRowAfterFirst: true) {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                    Text("Up Next")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ForEach(items) { item in
                    upNextRow(item)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()
        }
    }

    private func upNextRow(_ item: Item) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
            Text(item.name)
                .lineLimit(1)
            if item.count > 1 {
                Text("×\(item.count)")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if featureFlags.showingMultiplePackers, let user = item.user {
                Text(user.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }

    /// Visible lists split into grid rows of `columns`
    private var sectionRows: [[PackingList]] {
        let lists = visibleSections
        let size = max(columns, 1)
        return stride(from: 0, to: lists.count, by: size).map {
            Array(lists[$0..<min($0 + size, lists.count)])
        }
    }

    /// One list's name, bar, and count: three grid cells, so names and bars line up per column
    @ViewBuilder
    private func sectionCells(_ list: PackingList) -> some View {
        let packed = list.completeItems.count
        let total = list.totalItems
        let label = "\(list.name), \(packed) of \(total) packed"

        Text(list.name)
            .font(.subheadline)
            .lineLimit(1)
            .accessibilityLabel(label)

        ProgressView(value: Double(packed), total: Double(total))
            .tint(packed == total ? .green : .accent)
            .accessibilityHidden(true)

        Text("\(packed)/\(total)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
            .accessibilityHidden(true)
    }

    private func headline(packed: Int, total: Int) -> LocalizedStringKey {
        if total == 0 { return "Start Packing" }
        if packed == total { return "All Packed" }
        return "\(packed) of \(total) packed"
    }

    private func subtitle(packed: Int, total: Int) -> LocalizedStringKey {
        if total == 0 { return "Add items to your lists" }
        if packed == total { return "^[\(total) item](inflect: true) ready to go" }
        return "\(total - packed) left to pack"
    }
}

#Preview(traits: .sampleData) {
    @Previewable @Query var trips: [Trip]
    @Previewable @State var addingList = false
    @Previewable @State var applyingDefault = false
    NavigationStack {
        TripDetailPackingView(trip: trips.first!, isAddingNewPackingList: $addingList, isApplyingDefaultPackingList: $applyingDefault)
            .padding()
    }
}
