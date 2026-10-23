//
//  SettingsFormView.swift
//  PackingHelper
//
//  Created by Todd Louison on 6/23/24.
//

import SwiftUI
import SwiftData

import RevenueCat
import RevenueCatUI

enum PackerType: String, CaseIterable {
    case nightBefore = "Night Before"
    case morningOf = "Morning Of"
}

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
    @Environment(\.modelContext) private var modelContext
    @Environment(PurchaseManager.self) private var purchaseManager
    @Environment(\.dismiss) private var dismiss

    @Query private var users: [User]

    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @AppStorage("packerType") private var packerType = PackerType.nightBefore.rawValue
    @AppStorage("defaultLocation") private var defaultLocationData: Data = (try? JSONEncoder().encode(TripLocation.sampleOrigin)) ?? Data()
    @AppStorage("notificationTime") private var notificationMinutes = 480
    @AppStorage("autoCreateDefaultLists") private var autoCreateDefaultLists = true

    @State private var selectedTime = Date()
    #if DEBUG
    @State private var showDeveloperMenu = false
    #endif
    @State private var currentLocation: TripLocation = TripLocation.sampleOrigin
    @State private var displayPaywall: Bool = false
    @State private var displayCustomerCenter: Bool = false

    private var defaultLocation: Binding<TripLocation> {
        Binding(
            get: {
                if let location = try? JSONDecoder().decode(TripLocation.self, from: defaultLocationData) {
                    return location
                }
                return TripLocation.sampleDestination
            },
            set: { newLocation in
                if let encoded = try? JSONEncoder().encode(newLocation) {
                    defaultLocationData = encoded
                }
            }
        )
    }
    
    var body: some View {
        NavigationStack {
            Form {
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

                if FeatureFlags.shared.showingSubscription {
                    Section("Premium") {
                        //                    NavigationLink {
                        //                        PackingHelperPlusStoreView()
                        //                    } label: {
                        //                        Label {
                        //                            Text("Upgrade to Premium")
                        //                        } icon: {
                        //                            Image(systemName: "plus.square.fill")
                        //                                .foregroundStyle(defaultLinearGradient)
                        //                        }
                        //                    }
                        if purchaseManager.hasUnlockedPlus {
                            Button {
                                displayCustomerCenter = true
                            } label: {
                                Label {
                                    HStack {
                                        Text("Packing Helper Plus")
                                        Spacer()
                                        Text("Active")
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(defaultLinearGradient)
                                }
                            }
                        } else {
                            Button {
                                displayPaywall.toggle()
                            } label: {
                                Label {
                                    Text("Upgrade to Premium")
                                } icon: {
                                    Image(systemName: "plus.square.fill")
                                        .foregroundStyle(defaultLinearGradient)
                                }
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

                Section {
                    Toggle(isOn: $autoCreateDefaultLists) {
                        Label("Auto-create default lists", systemImage: "list.bullet.clipboard")
                    }
                } header: {
                    Text("Trip Defaults")
                } footer: {
                    Text("When enabled, new trips will automatically include empty default packing and task lists.")
                }
                
                if FeatureFlags.shared.showingNotifications {
                    Section(header: Text("Notification Preferences")) {
                        Picker("When do you pack?", selection: $packerType) {
                            ForEach(PackerType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type.rawValue)
                            }
                        }
                        
                        DatePicker(
                            "Notification Time",
                            selection: Binding(
                                get: {
                                    Calendar.current.date(from: DateComponents(hour: notificationMinutes / 60, minute: notificationMinutes % 60)) ?? Date()
                                },
                                set: { newValue in
                                    let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                                    notificationMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                                }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                    }
                }
                
                #if DEBUG
                Section("Developer") {
                    Button("Open Developer Menu") {
                        showDeveloperMenu = true
                    }
                }
                #endif
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            #if DEBUG
            .sheet(isPresented: $showDeveloperMenu) {
                DeveloperMenuView()
            }
            #endif
            .sheet(isPresented: $displayPaywall) {
                PlusPaywallView()
            }
            .presentCustomerCenter(isPresented: $displayCustomerCenter)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .confirm) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Update currentLocation with the stored value when the view appears
                let decodedLocation = DefaultLocationInformation.decode(from: defaultLocationData) ?? .default
                currentLocation = TripLocation(
                    name: decodedLocation.name,
                    latitude: decodedLocation.latitude,
                    longitude: decodedLocation.longitude
                )
            }
        }
    }
}

// Extension to help with accessing settings throughout the app
extension UserDefaults {
    var packerType: PackerType {
        PackerType(rawValue: string(forKey: "packerType") ?? PackerType.nightBefore.rawValue) ?? .nightBefore
    }
    
    var defaultLocation: String {
        string(forKey: "defaultLocation") ?? ""
    }
    
    var notificationTime: Date {
        let minutes = integer(forKey: "notificationTime")
        return Calendar.current.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60)) ?? Date()
    }

    var autoCreateDefaultLists: Bool {
        object(forKey: "autoCreateDefaultLists") == nil ? true : bool(forKey: "autoCreateDefaultLists")
    }
}


