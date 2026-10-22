//
//  PackingHelperApp.swift
//  PackingHelper
//
//  Created by Todd Louison on 10/9/23.
//

import SwiftUI
import SwiftData
import RevenueCat

@main
struct PackingHelperApp: App {
    @AppStorage("isDarkMode") private var isDarkMode = true
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore = false
    @AppStorage("hasMigratedDayOfLists") private var hasMigratedDayOfLists = false
    @AppStorage("hasMigratedSortOrders") private var hasMigratedSortOrders = false
    @AppStorage("hasMigratedDefaultLists") private var hasMigratedDefaultLists = false
    @AppStorage("hasMigratedPackingModelV2") private var hasMigratedPackingModelV2 = false
    @AppStorage("hasAssignedTemplateOwners") private var hasAssignedTemplateOwners = false

    @Environment(\.scenePhase) var scenePhase

    private var purchaseManager = PurchaseManager()

    let modelContainer: ModelContainer
    
    init() {
        do {
            modelContainer = try ModelContainer(for: Trip.self, TripLocation.self, PackingList.self, Item.self, TripCoverPhoto.self/*, Preferences.self*/)
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

        // Perform data migration if needed
        if !hasMigratedDayOfLists {
            migrateDayOfLists()
        }

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

    private func migrateDayOfLists() {
        let context = modelContainer.mainContext

        // Fetch all lists that were typed as dayOf
        // Since we changed the enum, we need to check the raw stored value
        let descriptor = FetchDescriptor<PackingList>()
        if let lists = try? context.fetch(descriptor) {
            for list in lists {
                // If the stored type was "Day-of", convert to packing with isDayOf = true
                if list.typeString == "Day-of" {
                    list.type = .packing
                    list.isDayOf = true
                }
            }
            try? context.save()
        }

        hasMigratedDayOfLists = true
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
                // Further group by type and isDayOf
                let grouped = Dictionary(grouping: tripLists) { "\($0.type.rawValue)-\($0.isDayOf)" }
                for (_, typeLists) in grouped {
                    for (index, list) in typeLists.enumerated() {
                        list.sortOrder = index
                        // Generate UUID if missing (for existing lists)
                        if list.uuid.uuidString == "00000000-0000-0000-0000-000000000000" {
                            list.uuid = UUID()
                        }
                    }
                }
            }
        }

        try? context.save()
        hasMigratedSortOrders = true
    }

    // Stamps list-level type/user/isDayOf onto each item, collapses to a single
    // default section per trip, and uses unifiedSortOrder as the canonical order.
    private func migratePackingModelV2() {
        let context = modelContainer.mainContext

        let listDescriptor = FetchDescriptor<PackingList>()
        guard let lists = try? context.fetch(listDescriptor) else {
            hasMigratedPackingModelV2 = true
            return
        }

        // Stamp list-level attributes onto items
        for list in lists {
            guard let items = list.items else { continue }
            for item in items {
                item.type = list.type
                item.isDayOf = list.isDayOf
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

                // Prefer the packing default as the survivor; demote all others
                let survivor = defaultLists.first(where: { $0.type == .packing }) ?? defaultLists[0]
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
                .preferredColorScheme(isDarkMode ? .dark : .light)
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
