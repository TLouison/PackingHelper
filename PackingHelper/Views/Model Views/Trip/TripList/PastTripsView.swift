//
//  PastTripsView.swift
//  PackingHelper
//
//  Completed trips, pushed from the Your Travels card in the trip list.
//

import SwiftUI
import SwiftData

struct PastTripsView: View {
    @Environment(TripsViewModel.self) private var viewModel

    private static var now: Date { Date.now }
    @Query(FetchDescriptor(
        predicate: #Predicate<Trip>{ $0.endDate <= now },
        // Most recently finished first
        sortBy: [SortDescriptor(\.endDate, order: .reverse)]
    ),
           animation: .snappy
    ) var completedTrips: [Trip]

    var body: some View {
        @Bindable var viewModel = viewModel

        Group {
            if completedTrips.isEmpty {
                ContentUnavailableView(
                    "No Past Trips",
                    systemImage: "airplane.arrival",
                    description: Text("Trips show up here once they end.")
                )
            } else {
                TripListScrollView(path: $viewModel.path, trips: completedTrips, showsPastTripsSummary: true)
            }
        }
        .navigationTitle("Past Trips")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden)
    }
}

#Preview(traits: .sampleData) {
    NavigationStack {
        PastTripsView()
    }
    .environment(TripsViewModel())
}
