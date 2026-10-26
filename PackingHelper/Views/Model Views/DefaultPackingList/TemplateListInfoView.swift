//
//  TemplateListInfoView.swift
//  PackingHelper
//
//  A read-only info sheet for template (default) packing lists, displaying
//  metadata such as creation date, item count, usage across trips, and more.
//

import SwiftUI
import SwiftData

struct TemplateListInfoView: View {
    let list: PackingList

    @Environment(\.dismiss) private var dismiss
    @State private var tripsExpanded: Bool = false

    private static let dateFormatter: Date.FormatStyle = .dateTime.month(.abbreviated).day().year()


    @ViewBuilder
    private func infoRow(_ title: String, _ detail: some View) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            detail
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("List Details") {
                    infoRow("Type", Label { Text(list.kind.displayName(isDayOf: list.isDayOf)) } icon: { list.glyph ?? list.kind.image })

                    infoRow("Total Items", Text("\(list.totalItems)"))

                    infoRow(
                        "Created",
                        Text(list.created.formatted(Self.dateFormatter))
                    )

                    infoRow(
                        "Last Updated",
                        Text(
                            list.lastUpdatedDate.map { $0.formatted(Self.dateFormatter) }
                                ?? "No items"
                        )
                    )
                }

                Section("Usage") {
                    DisclosureGroup(
                        isExpanded: $tripsExpanded,
                        content: {
                            let trips = list.appliedTrips
                            if trips.isEmpty {
                                Text("No trips yet")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            } else {
                                ForEach(trips.sorted(by: { $0.startDate < $1.startDate }), id: \.persistentModelID) { trip in
                                    HStack {
                                        Text(trip.name)
                                        
                                        Spacer()
                                        
                                        if trip.status == .complete {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .font(.subheadline)
                                }
                            }
                        },
                        label: {
                            infoRow(
                                "Applied to",
                                Text("\(list.appliedTrips.count) trip\(list.appliedTrips.count == 1 ? "" : "s")")
                            )
                        }
                    )

                    infoRow(
                        "Last Applied To",
                        Text(list.lastAppliedTrip?.name ?? "None")
                    )
                }
            }
            .navigationTitle("\(list.name) Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                }
            }
        }
    }
}
