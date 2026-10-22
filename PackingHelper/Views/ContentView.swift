//
//  ContentView.swift
//  PackingHelper
//
//  Created by Todd Louison on 10/9/23.
//

import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case trips, templates, packers, settings
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var selectedTab: AppTab = .trips

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Trips", systemImage: "airplane.departure", value: AppTab.trips) {
                TripListView()
            }

            Tab("Templates", systemImage: suitcaseIcon, value: AppTab.templates) {
                DefaultPackingListView()
            }

            if FeatureFlags.shared.showingMultiplePackers {
                Tab("Packers", systemImage: "person.circle", value: AppTab.packers) {
                    UserGridView()
                }
            }

            // Prominent role detaches Settings into its own group, apart from Trips/Templates
            Tab("Settings", systemImage: "gear", value: AppTab.settings, role: settingsTabRole) {
                SettingsView()
            }
        }
        .sheet(isPresented: Binding(
            get: { !hasCompletedOnboarding },
            set: { _ in }
        )) {
            OnboardingContainerView(modelContext: modelContext)
                .interactiveDismissDisabled()
        }
    }

    private var settingsTabRole: TabRole? {
        if #available(iOS 27.0, *) { .prominent } else { nil }
    }
}

@available(iOS 18.0, *)
#Preview(traits: .sampleData) {
    ContentView()
}
