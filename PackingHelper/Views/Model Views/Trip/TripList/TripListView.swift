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
    @State private var isShowingSettings: Bool = false
    @State private var isShowingCompletedTrips: Bool = false
    @State private var isCompletedTripDropdownOpen: Bool = false
    // System lays the toolbar out as a vertical bar beside the content
    @State private var isShowingVerticalToolbar: Bool = false
    
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
        // Most recently finished first
        sortBy: [SortDescriptor(\.endDate, order: .reverse)]
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
    
    /// Past trips with items that could be saved back to their templates
    var pastTripTemplateReviewCount: Int {
        completedTrips.count(where: \.showsTemplateReviewCard)
    }

    /// Only while the button leads to past trips; zero hides the badge
    var pastTripsBadgeCount: Int {
        isShowingCompletedTrips || users.isEmpty || completedTrips.isEmpty ? 0 : pastTripTemplateReviewCount
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
            TripListScrollView(path: $viewModel.path, trips: completedTrips, showsPastTripsSummary: true)
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
    
    @ViewBuilder
    var visibleTripsToggle: some View {
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
            .accessibilityLabel(isShowingCompletedTrips ? "Show Upcoming Trips" : "Show Past Trips")
            .accessibilityValue(
                pastTripsBadgeCount > 0
                    ? Text("^[\(pastTripsBadgeCount) trip](inflect: true) with items to review")
                    : Text(verbatim: "")
            )
            // System toolbar badge stays opaque; custom overlays pick up the glass vibrancy
            .badge(pastTripsBadgeCount)
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
            .sheet(isPresented: $isShowingAddTripSheet, onDismiss: openNewlyCreatedTrip) {
                TripEditView(trip: nil, isDeleted: .constant(false)) { trip in
                    newlyCreatedTrip = trip
                }
            }
            .toolbar {
                if isShowingVerticalToolbar {
                    // Vertical bar reads top to bottom: Settings, trip toggle, then Add down by the tabs
                    ToolbarItem(placement: .topBarLeading) {
                        settingsButton
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        visibleTripsToggle
                    }
                    ToolbarItem(placement: .bottomBar) {
                        addTripButton
                    }
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        visibleTripsToggle
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        settingsButton
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    ToolbarItem(placement: .topBarTrailing) {
                        addTripButton
                    }
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

    func toggleVisibleTrips() {
        isShowingCompletedTrips.toggle()
        // Toggle symbol to other symbol
        visibleTripsSymbol = switch visibleTripsSymbol {
        case .completed: .upcoming
        case .upcoming: .completed
        }
    }
}

private extension View {
    func readsVerticalToolbar(_ isVertical: Binding<Bool>) -> some View {
        modifier(VerticalToolbarReader(isVertical: isVertical))
    }
}

private struct VerticalToolbarReader: ViewModifier {
    @Binding var isVertical: Bool

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.modifier(ToolbarVerticalEdgeObserver(isVertical: $isVertical))
        } else {
            content
        }
    }
}

@available(iOS 27.1, *)
private struct ToolbarVerticalEdgeObserver: ViewModifier {
    @Environment(\.toolbarVerticalEdge) private var toolbarVerticalEdge
    @Binding var isVertical: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: toolbarVerticalEdge != nil, initial: true) { _, isPresent in
                isVertical = isPresent
            }
    }
}

@available(iOS 18.0, *)
#Preview(traits: .sampleData) {
    TripListView()
}
