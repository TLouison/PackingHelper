//
//  ContentView.swift
//  PackingHelper
//
//  Created by Todd Louison on 10/9/23.
//

import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case trips, templates, packers
}

struct ContentView: View {
    @AppStorage(StorageKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @State private var selectedTab: AppTab = .trips
    /// Bumped when the Trips tab is tapped while already selected
    @State private var tripsTabReselections = 0

    private static var now: Date { Date.now }
    @Query(filter: #Predicate<Trip> { $0.endDate <= now }) private var completedTrips: [Trip]

    /// Past trips with items that could be saved back to their templates
    private var templateReviewCount: Int {
        completedTrips.count(where: \.showsTemplateReviewCard)
    }

    var body: some View {
        TabView(selection: tabSelection) {
            Tab("Trips", systemImage: "airplane.departure", value: AppTab.trips) {
                TripListView(reselections: tripsTabReselections)
            }

            Tab("Templates", systemImage: suitcaseIcon, value: AppTab.templates) {
                DefaultPackingListView()
            }
            .badge(templateReviewCount)

            if FeatureFlags.shared.showingMultiplePackers {
                Tab("Packers", systemImage: "person.circle", value: AppTab.packers) {
                    UserGridView()
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { !hasCompletedOnboarding },
            set: { _ in }
        )) {
            WelcomeView()
                .interactiveDismissDisabled()
        }
    }
}

extension ContentView {
    /// The tab bar sets the selection again when the current tab is tapped; catch that for Trips
    private var tabSelection: Binding<AppTab> {
        Binding {
            selectedTab
        } set: { tab in
            if tab == selectedTab && tab == .trips {
                tripsTabReselections += 1
            }
            selectedTab = tab
        }
    }
}

@available(iOS 18.0, *)
#Preview(traits: .sampleData) {
    ContentView()
}
