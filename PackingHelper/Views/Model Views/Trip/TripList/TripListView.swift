//
//  TripListView.swift
//  PackingHelper
//
//  Created by Todd Louison on 10/13/23.
//

import SwiftUI
import SwiftData
import MapKit

@Observable class TripsViewModel {
    var path: NavigationPath = .init()
}

/// Non-trip destinations pushed onto the trip list's navigation path
enum TripListRoute: Hashable {
    case pastTrips
}

struct TripListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = TripsViewModel()
    
    @State private var isShowingAddTripSheet: Bool = false
    @State private var isShowingSettings: Bool = false
    // System lays the toolbar out as a vertical bar beside the content
    @State private var isShowingVerticalToolbar: Bool = false

    // Opened once the create sheet finishes dismissing
    @State private var newlyCreatedTrip: Trip?
    
    private static var now: Date { Date.now }
    @Query(FetchDescriptor(
        predicate: #Predicate<Trip>{ $0.endDate > now },
        sortBy: [SortDescriptor(\.startDate, order: .forward)]
    ),
           animation: .snappy
    ) var upcomingTrips: [Trip]
    
    @Query(FetchDescriptor(
        predicate: #Predicate<Trip>{ $0.endDate <= now },
        // Most recently finished first
        sortBy: [SortDescriptor(\.endDate, order: .reverse)]
    ),
           animation: .snappy
    ) var completedTrips: [Trip]
    @Query private var users: [User]
    
    var atMaxFreeTrips: Bool {
        upcomingTrips.count >= Trip.maxFreeTrips
    }
    
    var viewTitle: String {
        upcomingTrips.isEmpty ? "" : "Upcoming Trips"
    }
    
    var allTripsCompletedView: some View {
        ContentUnavailableView {
            TripType.plane.startLabel(text: "No Upcoming Trips")
        } description: {
            Text("Every trip is done. Add your next one to start packing.")
        } actions: {
            EmptyStateButton(title: "Create Trip", systemImage: "plus") {
                isShowingAddTripSheet.toggle()
            }
            EmptyStateButton(title: "View Past Trips", systemImage: "globe.americas.fill", isProminent: false) {
                viewModel.path.append(TripListRoute.pastTrips)
            }
        }
    }
    
    var noTripsAddedView: some View {
        ContentUnavailableView {
            Label("No Trips Yet", systemImage: "airplane.departure")
        } description: {
            Text("Add where and when you're going to start a packing list.")
        } actions: {
            EmptyStateButton(title: "Create Trip", systemImage: "plus") {
                isShowingAddTripSheet.toggle()
            }
        }
    }
    
    @ViewBuilder
    func tripList() -> some View {
        if !upcomingTrips.isEmpty {
            TripListScrollView(path: $viewModel.path, trips: upcomingTrips, canShowCTA: true, pastTrips: completedTrips)
        } else if !completedTrips.isEmpty {
            allTripsCompletedView
                .navigationTitle("Trips")
        } else {
            noTripsAddedView
                .navigationTitle("Trips")
        }
    }
    
    @ViewBuilder
    var listView: some View {
        if users.isEmpty {
            MissingUsersView()
        } else {
            tripList()
        }
    }
    
    var settingsButton: some View {
        Button("Settings", systemImage: "gear") {
            isShowingSettings = true
        }
    }

    @ViewBuilder
    var addTripButton: some View {
        if !users.isEmpty {
            SubscriptionAwareButton(localLimitMet: atMaxFreeTrips) {
                withAnimation {
                    isShowingAddTripSheet.toggle()
                }
            } label: {
                Label("Add Trip", systemImage: "plus")
                    .symbolEffect(.bounce.down, value: isShowingAddTripSheet)
            }
        }
    }

    var body: some View {
        NavigationStack(path: $viewModel.path) {
            listView
            .navigationTitle(viewTitle)
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Trip.self) { trip in
                TripDetailView(trip: trip)
            }
            .navigationDestination(for: TripListRoute.self) { route in
                switch route {
                case .pastTrips: PastTripsView()
                }
            }
            .sheet(isPresented: $isShowingAddTripSheet, onDismiss: openNewlyCreatedTrip) {
                TripEditView(trip: nil, isDeleted: .constant(false)) { trip in
                    newlyCreatedTrip = trip
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    settingsButton
                }
                // Vertical bar: Add sits in the lower group, down by the tabs
                ToolbarItem(placement: isShowingVerticalToolbar ? .bottomBar : .topBarTrailing) {
                    addTripButton
                }
            }
            .toolbarBackground(.hidden)
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
        }
        .readsVerticalToolbar($isShowingVerticalToolbar)
        .environment(viewModel)
    }
    
    func openNewlyCreatedTrip() {
        guard let trip = newlyCreatedTrip else { return }
        newlyCreatedTrip = nil
        viewModel.path.append(trip)
    }
}

@available(iOS 18.0, *)
#Preview(traits: .sampleData) {
    TripListView()
}
