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
        }
        .sheet(isPresented: Binding(
            get: { !hasCompletedOnboarding },
            set: { _ in }
        )) {
            OnboardingContainerView(modelContext: modelContext)
                .interactiveDismissDisabled()
        }
    }
}

@available(iOS 18.0, *)
#Preview(traits: .sampleData) {
    ContentView()
}
