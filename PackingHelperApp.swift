//
//  PackingHelperApp.swift
//  PackingHelper
//
//  Created by Todd Louison on 10/9/23.
//

import SwiftUI
import SwiftData
import RevenueCat
import TipKit

@main
struct PackingHelperApp: App {
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore = false
    @AppStorage("hasMigratedSortOrders") private var hasMigratedSortOrders = false
    @AppStorage("hasMigratedDefaultLists") private var hasMigratedDefaultLists = false
    @AppStorage("hasMigratedPackingModelV2") private var hasMigratedPackingModelV2 = false
    @AppStorage("hasAssignedTemplateOwners") private var hasAssignedTemplateOwners = false

    @Environment(\.scenePhase) var scenePhase

    @State private var purchaseManager = PurchaseManager()

    let modelContainer: ModelContainer
    
    init() {
        do {
            modelContainer = try ModelContainer(for: Trip.self, TripLocation.self, PackingList.self, Item.self, TripCoverPhoto.self)
        } catch {
            fatalError("Could not initialize ModelContainer")
        }

        // Configure RevenueCat to manage purchases (Test Store in dev, App Store
        // in prod). RC records the "PackingHelperPlus" entitlement so the AI
        // Worker can verify it via its REST API; PurchaseManager mirrors it.
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: REVENUECAT_PUBLIC_API_KEY)

        // Feature tips (PackingTips.swift). The datastore can only be reset before configuring.
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "resetTipsOnLaunch") {
            try? Tips.resetDatastore()
            UserDefaults.standard.set(false, forKey: "resetTipsOnLaunch")
        }
        #endif
        try? Tips.configure()

        // Perform data migration if needed
        if !hasMigratedSortOrders {
            migrateSortOrders()
        }

        if !hasMigratedDefaultLists {
            migrateDefaultLists()
        }

        if !hasMigratedPackingModelV2 {
            migratePackingModelV2()
        }

        if !hasAssignedTemplateOwners {
            assignTemplateOwners()
        }
    }

    // Templates are owned by a packer; give ownerless ones to the first packer.
    // Retried next launch if no packers exist yet.
    private func assignTemplateOwners() {
        let context = modelContainer.mainContext

        let userDescriptor = FetchDescriptor<User>(sortBy: [SortDescriptor(\.created, order: .forward)])
        guard let firstPacker = (try? context.fetch(userDescriptor))?.first else { return }

        let templateDescriptor = FetchDescriptor<PackingList>(
            predicate: #Predicate<PackingList> { $0.template == true }
        )
        if let templates = try? context.fetch(templateDescriptor) {
            for template in templates where template.user == nil {
                template.user = firstPacker
            }
            try? context.save()
        }

        hasAssignedTemplateOwners = true
    }

    private func migrateSortOrders() {
        let context = modelContainer.mainContext

        // Migrate Items - set initial sort orders based on creation date
        let itemDescriptor = FetchDescriptor<Item>(
            sortBy: [SortDescriptor(\.created, order: .forward)]
        )
        if let items = try? context.fetch(itemDescriptor) {
            // Group items by list for list-specific ordering
            let itemsByList = Dictionary(grouping: items) { $0.list?.persistentModelID }

            for (_, listItems) in itemsByList {
                for (index, item) in listItems.enumerated() {
                    item.sortOrder = index
                    // Generate UUID if missing (for existing items)
                    if item.uuid.uuidString == "00000000-0000-0000-0000-000000000000" {
                        item.uuid = UUID()
                    }
                }
            }

            // Set unified sort order globally
            for (index, item) in items.enumerated() {
                item.unifiedSortOrder = index
            }
        }

        // Migrate PackingLists - set initial sort orders based on creation date
        let listDescriptor = FetchDescriptor<PackingList>(
            sortBy: [SortDescriptor(\.created, order: .forward)]
        )
        if let lists = try? context.fetch(listDescriptor) {
            // Group by trip for trip-specific ordering
            let listsByTrip = Dictionary(grouping: lists) { $0.trip?.persistentModelID }

            for (_, tripLists) in listsByTrip {
                for (index, list) in tripLists.enumerated() {
                    list.sortOrder = index
                    // Generate UUID if missing (for existing lists)
                    if list.uuid.uuidString == "00000000-0000-0000-0000-000000000000" {
                        list.uuid = UUID()
                    }
                }
            }
        }

        try? context.save()
        hasMigratedSortOrders = true
    }

    // Stamps the list-level user onto each item, collapses to a single
    // default section per trip, and uses unifiedSortOrder as the canonical order.
    private func migratePackingModelV2() {
        let context = modelContainer.mainContext

        let listDescriptor = FetchDescriptor<PackingList>()
        guard let lists = try? context.fetch(listDescriptor) else {
            hasMigratedPackingModelV2 = true
            return
        }

        // Stamp the list-level user onto items
        for list in lists {
            guard let items = list.items else { continue }
            for item in items {
                item.user = list.user
                // Use the old unified sort order as the new single sort order if it was set
                if item.unifiedSortOrder > 0 {
                    item.sortOrder = item.unifiedSortOrder
                }
            }
        }

        // Per trip: keep exactly one isDefault catch-all section
        let tripDescriptor = FetchDescriptor<Trip>()
        if let trips = try? context.fetch(tripDescriptor) {
            for trip in trips {
                let defaultLists = (trip.lists ?? []).filter { $0.isDefault }
                guard !defaultLists.isEmpty else { continue }

                // Keep the first; demote all others
                let survivor = defaultLists[0]
                for list in defaultLists where list.persistentModelID != survivor.persistentModelID {
                    list.isDefault = false
                }
            }
        }

        try? context.save()
        hasMigratedPackingModelV2 = true
    }

    private func migrateDefaultLists() {
        let context = modelContainer.mainContext

        let tripDescriptor = FetchDescriptor<Trip>()

        if let trips = try? context.fetch(tripDescriptor) {
            for trip in trips {
                let hasDefault = trip.lists?.contains { $0.isDefault } ?? false
                if !hasDefault {
                    PackingList.createDefaultList(for: trip, in: context)
                }
            }
            try? context.save()
        }

        hasMigratedDefaultLists = true
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(AppearanceMode(rawValue: appearanceMode)?.colorScheme)
                .environment(purchaseManager)
                .task {
                    await purchaseManager.start()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task { await purchaseManager.refresh() }
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}
