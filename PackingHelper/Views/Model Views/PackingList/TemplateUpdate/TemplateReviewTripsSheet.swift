//
//  TemplateReviewTripsSheet.swift
//  PackingHelper
//
//  Past trips with items to save back to their templates, opened from the Templates tab.
//

import SwiftUI
import SwiftData

struct TemplateReviewTripsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private static var now: Date { Date.now }
    @Query(FetchDescriptor(
        predicate: #Predicate<Trip> { $0.endDate <= now },
        // Most recently finished first
        sortBy: [SortDescriptor(\.endDate, order: .reverse)]
    ),
           animation: .snappy
    ) private var completedTrips: [Trip]

    @State private var reviewingTrip: Trip?

    private var reviewTrips: [Trip] {
        completedTrips.filter(\.showsTemplateReviewCard)
    }

    var body: some View {
        let reviewTrips = self.reviewTrips

        NavigationStack {
            Group {
                if reviewTrips.isEmpty {
                    ContentUnavailableView(
                        "Templates Are Up to Date",
                        systemImage: "checkmark.circle",
                        description: Text("Items and lists you add on future trips will show up here once those trips end.")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Save what you added on past trips to your templates, or keep new lists as templates.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 8)

                            ForEach(reviewTrips) { trip in
                                TemplateReviewTripRow(trip: trip) {
                                    reviewingTrip = trip
                                } onDismiss: {
                                    withAnimation {
                                        trip.templateReviewDismissed = true
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Items to Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $reviewingTrip) { trip in
            TemplateUpdateSheet(trip: trip) {
                trip.templateReviewDismissed = true
            }
        }
    }
}

@available(iOS 18.0, *)
#Preview(traits: .sampleData) {
    TemplateReviewTripsSheet()
}
