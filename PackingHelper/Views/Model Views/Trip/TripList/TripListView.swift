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

struct TripListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = TripsViewModel()
    
    @State private var isShowingAddTripSheet: Bool = false
    @State private var isShowingCompletedTrips: Bool = false
    @State private var isCompletedTripDropdownOpen: Bool = false
    
    @State private var visibleTripsSymbol: Symbol = .upcoming

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
        sortBy: [SortDescriptor(\.startDate, order: .forward)]
    ),
           animation: .snappy
    ) var completedTrips: [Trip]
    @Query private var users: [User]
    
    enum Symbol: Hashable, CaseIterable {
        case completed, upcoming
        
        var name: String {
            switch self {
            case .completed: return "airplane.arrival"
            case .upcoming: return "airplane.departure"
            }
        }
    }
    
    var atMaxFreeTrips: Bool {
        upcomingTrips.count >= Trip.maxFreeTrips
    }
    
    var viewTitle: String {
        if isShowingCompletedTrips && !completedTrips.isEmpty {
            return "Completed Trips"
        } else if !upcomingTrips.isEmpty {
            return "Upcoming Trips"
        } else {
            return ""
        }
    }
    
    var allTripsCompletedView: some View {
        ContentUnavailableView {
            TripType.plane.startLabel(text: "No Upcoming Trips")
        } description: {
            Text("You've completed all of your trips! Add a new one to start packing.")
        } actions: {
            Button("Create Trip", systemImage: "folder.badge.plus") {
                isShowingAddTripSheet.toggle()
            }
        }
    }
    
    var noTripsAddedView: some View {
        ContentUnavailableView {
            Label("No Trips", systemImage: "airplane")
        } description: {
            Text("Add a trip to get started with your packing!")
        } actions: {
            Button("Create Trip", systemImage: "folder.badge.plus") {
                isShowingAddTripSheet.toggle()
            }
        }
    }
    
    @ViewBuilder
    func tripList() -> some View {
        if !completedTrips.isEmpty && isShowingCompletedTrips {
            TripListScrollView(path: $viewModel.path, trips: completedTrips)
                .transition(.pushAndPull(.leading))
        } else if !upcomingTrips.isEmpty {
            TripListScrollView(path: $viewModel.path, trips: upcomingTrips, canShowCTA: true)
                .transition(.pushAndPull(.trailing))
        } else if upcomingTrips.isEmpty && !completedTrips.isEmpty {
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
    
    var body: some View {
        NavigationStack(path: $viewModel.path) {
            listView
            .navigationTitle(viewTitle)
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Trip.self) { trip in
                TripDetailView(trip: trip)
            }
            .sheet(isPresented: $isShowingAddTripSheet, onDismiss: openNewlyCreatedTrip) {
                TripEditView(trip: nil, isDeleted: .constant(false)) { trip in
                    newlyCreatedTrip = trip
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    if !users.isEmpty && !completedTrips.isEmpty {
                        Button {
                            withAnimation {
                                toggleVisibleTrips()
                            }
                        } label: {
                            HStack {
                                Image(systemName: visibleTripsSymbol.name)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(visibleTripsSymbol == .completed ? Color.green.gradient : Color.accentColor.gradient)
                                    .contentTransition(
                                        .symbolEffect(.replace.downUp.byLayer)
                                    )
                                    .symbolEffect(.bounce, value: visibleTripsSymbol == .completed ? upcomingTrips.count : completedTrips.count)
                                    .labelStyle(.titleAndIcon)
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
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
            }
            .toolbarBackground(.hidden)
        }
        .environment(viewModel)
    }
    
    func openNewlyCreatedTrip() {
        guard let trip = newlyCreatedTrip else { return }
        newlyCreatedTrip = nil
        viewModel.path.append(trip)
    }

    func toggleVisibleTrips() {
        isShowingCompletedTrips.toggle()
        // Toggle symbol to other symbol
        visibleTripsSymbol = switch visibleTripsSymbol {
        case .completed: .upcoming
        case .upcoming: .completed
        }
    }
}

@available(iOS 18.0, *)
#Preview(traits: .sampleData) {
    TripListView()
}
