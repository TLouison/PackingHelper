//
//  SettingsFormView.swift
//  PackingHelper
//
//  Created by Todd Louison on 6/23/24.
//

import SwiftUI
import SwiftData

enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    // nil lets the app follow the system setting
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @Query private var users: [User]

    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue

    #if DEBUG
    @State private var showDeveloperMenu = false
    #endif

    var body: some View {
        NavigationStack {
            Form {
                PlusSettingsSection()

                if !FeatureFlags.shared.showingMultiplePackers, let firstUser = users.first {
                    Section("Your Profile") {
                        NavigationLink {
                            UserEditView(user: firstUser)
                        } label: {
                            HStack {
                                firstUser.pillFirstInitialIconSolid
                                Text(firstUser.name)
                                Spacer()
                            }
                        }
                    }
                }

                Section("Appearance") {
                    Picker(selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode.rawValue)
                        }
                    } label: {
                        Label("Theme", systemImage: "circle.lefthalf.filled")
                    }
                }

                TripSettingsSection()

                AboutSettingsSection()

                #if DEBUG
                Section("Developer") {
                    Button {
                        showDeveloperMenu = true
                    } label: {
                        Label("Developer Menu", systemImage: "hammer")
                    }
                }
                #endif
            }
            #if DEBUG
            .sheet(isPresented: $showDeveloperMenu) {
                DeveloperMenuView()
            }
            #endif
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .confirm) {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Preferences that shape trips. Each setting gets its own section so its
/// explanation sits directly under it as the footer.
private struct TripSettingsSection: View {
    @AppStorage("autoCreateDefaultLists") private var autoCreateDefaultLists = false
    @AppStorage("defaultTripCover") private var defaultTripCover = DefaultTripCover.photo.rawValue
    @AppStorage(PackingStartPage.storageKey) private var packingStartPage = PackingStartPage.firstList.rawValue

    var body: some View {
        Section {
            Toggle(isOn: $autoCreateDefaultLists) {
                Label("Add a Default List", systemImage: "list.bullet.clipboard")
            }
        } header: {
            Text("Trips")
        } footer: {
            Text("New trips start with an empty list named \(PackingList.defaultListName).")
        }

        Section {
            Picker(selection: $defaultTripCover) {
                ForEach(DefaultTripCover.allCases, id: \.self) { cover in
                    Text(cover.rawValue).tag(cover.rawValue)
                }
            } label: {
                Label("Default Cover", systemImage: "photo")
            }
        } footer: {
            Text(coverFooter)
        }

        Section {
            Picker(selection: $packingStartPage) {
                ForEach(PackingStartPage.allCases, id: \.self) { page in
                    Text(page.rawValue).tag(page.rawValue)
                }
            } label: {
                Label("Open Packing On", systemImage: "rectangle.stack")
            }
        } footer: {
            Text(packingStartPage == PackingStartPage.all.rawValue
                ? "Packing opens on every item from all your lists."
                : "Packing opens on your first list.")
        }
    }

    private var coverFooter: String {
        defaultTripCover == DefaultTripCover.map.rawValue
            ? "New trips show the destination map until you choose a photo."
            : "New trips get a random photo of the destination. You can change it."
    }
}

private struct AboutSettingsSection: View {
    @Environment(PurchaseManager.self) private var purchaseManager

    @State private var isRestoring = false
    @State private var restoreMessage: String?

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    var body: some View {
        Section("About") {
            LabeledContent("Version", value: versionString)

            if !purchaseManager.isPlusActive {
                Button {
                    restore()
                } label: {
                    HStack {
                        Label("Restore Purchases", systemImage: "arrow.clockwise")
                        Spacer()
                        if isRestoring {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRestoring)
            }
        }
        .alert(
            "Restore Purchases",
            isPresented: Binding(
                get: { restoreMessage != nil },
                set: { if !$0 { restoreMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreMessage ?? "")
        }
    }

    private func restore() {
        isRestoring = true
        Task {
            defer { isRestoring = false }
            do {
                let restored = try await purchaseManager.restore()
                restoreMessage = restored
                    ? "Packing Helper Plus has been restored."
                    : "No previous Packing Helper Plus purchase was found for this Apple Account."
            } catch {
                restoreMessage = "Purchases couldn't be restored. Check your connection and try again."
            }
        }
    }
}

#Preview(traits: .sampleData) {
    SettingsView()
        .environment(PurchaseManager())
}
