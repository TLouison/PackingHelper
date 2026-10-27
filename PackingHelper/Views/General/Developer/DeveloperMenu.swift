//
//  DeveloperMenu.swift
//  PackingHelper
//
//  Created by Todd Louison on 1/1/25.
//

import SwiftUI
import SwiftData

#if DEBUG
struct DeveloperMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage(StorageKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @AppStorage(StorageKey.resetTipsOnLaunch) private var resetTipsOnLaunch = false
    @Query private var users: [User]
    @State private var featureFlagsExpanded = true
    @State private var featureFlags = FeatureFlags.shared
    @State private var showingOnboardingPreview = false

    var body: some View {
        NavigationStack {
            List {
                VStack(spacing: 20) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow.gradient)
                        Text("Developer Menu")
                    }.font(.title)
                    Text("This menu is for development purposes only, and contains features that are not intended to be used currently.").font(.headline)
                    Text("If you encounter any issues with any of these features, do not report those issues. They are still works in progress. If you wish to retest the onboarding flow, you can do so below, but it will ERASE your user and lists, which is irreversible.").fixedSize(horizontal: false, vertical: true)
                }
                
                Section {
                    Button("Preview Onboarding") {
                        showingOnboardingPreview = true
                    }
                } footer: {
                    Text("Preview the welcome screen without affecting your data.").font(.subheadline)
                }

                Section {
                    Button("Reset Onboarding State") {
                        hasCompletedOnboarding = false
                        users.forEach { modelContext.delete($0) }
                        try? modelContext.save()
                        dismiss()
                    }
                } header: {
                    Text("Reset Onboarding")
                } footer: {
                    Text("Resetting onboarding state will wipe out all trips and users. Be sure you want to do this, it cannot be undone.").font(.subheadline)
                }
                
                Section {
                    Toggle("Reset Tips on Next Launch", isOn: $resetTipsOnLaunch)
                } footer: {
                    Text("Shows every feature tip again after you relaunch the app.").font(.subheadline)
                }

                Section {
                    DisclosureGroup("Feature Flags", isExpanded: $featureFlagsExpanded) {
                        Toggle("Multiple Packers", isOn: $featureFlags.showingMultiplePackers)
                        Toggle("User Profile Pictures", isOn: $featureFlags.showingProfilePictures)
                        Toggle("Notifications", isOn: $featureFlags.showingNotifications)
                        Toggle("Packing Engine", isOn: $featureFlags.showingPackingEngine)
                    }
                } footer: {
                    Text("Enable or disable experimental features for testing.").font(.subheadline)
                }

                Section("Debug Info") {
                    LabeledContent("Onboarding Completed") {
                        Text(hasCompletedOnboarding ? "Yes" : "No")
                    }
                    if let user = users.first {
                        LabeledContent("User Name") { Text(user.name) }
                        LabeledContent("Icon Color") { Text(user.colorHex) }
                    }
                }
            }
            .navigationTitle("Developer Menu")
            .sheet(isPresented: $showingOnboardingPreview) {
                WelcomeView(isPreview: true)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    DeveloperMenuView()
}
#endif
