//
//  Trip.swift
//  PackingHelper
//
//  Created by Todd Louison on 10/9/23.
//

import Foundation
import SwiftData
import SwiftUI
import OSLog

enum TripType: Codable, CaseIterable {
    case plane, car, train, boat, ferry

    var name: String {
        switch self {
        case .plane: "Plane"
        case .car: "Car"
        case .boat: "Boat"
        case .train: "Train"
        case .ferry: "Ferry"
        }
    }

    @ViewBuilder
    func startLabel(text: String) -> some View {
        Label(
            title: { Text(text) },
            icon: { self.startIcon }
        )
    }

    @ViewBuilder
    func endLabel(text: String) -> some View {
        Label(
            title: { Text(text) },
            icon: { self.endIcon }
        )
    }

    var startIcon: Image {
        switch self {
            case .plane:
                return Image(systemName: "airplane.departure")
            case .train:
                return Image(systemName: "train.side.front.car")
            case .car:
                return Image(systemName: "car")
            case .ferry:
                return Image(systemName: "car.ferry")
            case .boat:
                return Image(systemName: "ferry")
        }
    }

    var endIcon: Image {
        switch self {
            case .plane:
                return Image(systemName: "airplane.arrival")
            case .train:
                return Image(systemName: "train.side.front.car")
            case .car:
                return Image(systemName: "car")
            case .ferry:
                return Image(systemName: "car.ferry")
            case .boat:
                return Image(systemName: "ferry")
        }
    }
}

enum TripAccomodation: Codable, CaseIterable {
    case hotel, rental, family, friend

    var name: String {
        switch self {
        case .family: "Family"
        case .friend: "Friend"
        case .hotel: "Hotel"
        case .rental: "Rental"
        }
    }
}

@Model
final class Trip {
    enum TripStatus {
        case upcoming, departing, active, returning, complete
    }

    var uuid: UUID = UUID()
    var name: String = "Trip"

    @Relationship var origin: TripLocation?
    @Relationship var destination: TripLocation?
    @Relationship(deleteRule: .cascade, inverse: \PackingList.trip) var lists: [PackingList]? = []
    @Relationship(deleteRule: .cascade, inverse: \TripCoverPhoto.trip) var coverPhoto: TripCoverPhoto?

    var startDate: Date = Date.now
    var endDate: Date = Date.now.advanced(by: SECONDS_IN_DAY)
    var createdDate: Date = Date.now

    var type: TripType = TripType.plane
    var accomodation: TripAccomodation = TripAccomodation.hotel

    var dayOfNotificationUUID: String?

    static let maxFreeTrips: Int = 3

    init(name: String, startDate: Date, endDate: Date, type: TripType, origin: TripLocation?, destination: TripLocation, accomodation: TripAccomodation) {
        self.createdDate = Date.now

        self.name = name

        self.startDate = startDate
        self.endDate = endDate

        self.type = type
        self.accomodation = accomodation

        self.origin = origin
        self.destination = destination

        if FeatureFlags.shared.showingNotifications {
            self.createDayOfPackingNotification()
        }
    }

    static func create_or_update(
        _ trip: Trip?,
        name: String,
        startDate: Date,
        endDate: Date,
        tripType: TripType,
        origin: TripLocation,
        destination: TripLocation,
        accomodation: TripAccomodation,
        in context: ModelContext
    ) -> Trip {
        if let trip {
            trip.name = name

            trip.startDate = startDate
            trip.endDate = endDate

            trip.type = tripType
            trip.accomodation = accomodation

            trip.origin = origin
            trip.destination = destination
            return trip
        } else {
            let newTrip = Trip(
                name: name,
                startDate: startDate,
                endDate: endDate,
                type: tripType,
                origin: origin,
                destination: destination,
                accomodation: accomodation
            )
            context.insert(newTrip)
            return newTrip
        }
    }

    static func delete(_ trip: Trip, in context: ModelContext) {
        context.delete(trip)
    }
}

extension Trip {
    var complete: Bool {
        return Date.now >= self.endDate
    }

    var status: TripStatus {
        if Date.now < self.startDate {
            return .upcoming
        } else if Date.now == self.startDate {
            return .departing
        } else if Date.now == self.endDate {
            return .returning
        } else if Date.now > self.endDate {
            return .complete
        } else {
            return .active
        }
    }

    @ViewBuilder
    func getStatusLabel() -> some View {
        switch self.status {
        case .upcoming, .departing:
            Text("Upcoming")
        case .returning, .complete:
            Text("Complete")
        default:
            Text("In Progress")
        }
    }

    @ViewBuilder
    func getTypeLabel() -> some View {
        switch self.status {
        case .upcoming, .departing:
            self.type.startLabel(text: "\(self.type.name)")
        case .returning, .complete:
            self.type.endLabel(text: "\(self.type.name)")
        default:
            self.type.startLabel(text: "\(self.type.name)")
        }
    }
}

// List-related Trip Code
extension Trip {
    // Flat array of all items across all sections
    var allItems: [Item] {
        (lists ?? []).flatMap { $0.items ?? [] }
    }

    // MARK: Item counts (item-level attributes)
    var totalItemsCount: Int { allItems.count }
    var packedItemsCount: Int { allItems.filter { $0.isPacked }.count }
    var incompleteItemsCount: Int { allItems.filter { !$0.isPacked }.count }

    // MARK: Default list accessors
    var defaultPackingList: PackingList? {
        lists?.first(where: { $0.isDefault })
    }

    // Legacy accessor — always nil in v2 model (single default list per trip)
    var defaultTaskList: PackingList? { nil }

    var hasDefaultLists: Bool {
        defaultPackingList != nil
    }

    // MARK: List metadata (item-based)
    var hasMultiplePackers: Bool {
        return self.packers.count > 1
    }

    var packers: [User] {
        return Array(Set(allItems.compactMap { $0.user }))
    }

    var containsListTypes: [ListType] {
        return Array(Set(allItems.map { $0.type })).sorted()
    }

    var containsDayOfPacking: Bool {
        return allItems.contains { $0.isDayOf && $0.type == .packing }
    }

    var containsDayOfTask: Bool {
        return allItems.contains { $0.isDayOf && $0.type == .task }
    }

    var listsFromTemplates: [PackingList] {
        return self.lists?.filter { $0.appliedFromTemplate != nil } ?? []
    }

    var alreadyUsedTemplates: [PackingList] {
        return self.listsFromTemplates.compactMap { $0.appliedFromTemplate }
    }

    // MARK: Item counts — item-based (replaces list-type-filtered overloads)
    var totalListEntries: Int { totalItemsCount }

    var totalIncompletePackingItemsEntries: Int {
        allItems.filter { !$0.isPacked && $0.type == .packing }.count
    }

    func getTotalItems(for itemType: ListType) -> Int {
        return allItems.filter { $0.type == itemType }.count
    }

    func getTotalItems(for itemType: ListType, isDayOf: Bool) -> Int {
        return allItems.filter { $0.type == itemType && $0.isDayOf == isDayOf }.count
    }

    func getIncompleteItems(for itemType: ListType) -> Int {
        return allItems.filter { $0.type == itemType && !$0.isPacked }.count
    }

    func getIncompleteItems(for itemType: ListType, isDayOf: Bool) -> Int {
        return allItems.filter { $0.type == itemType && $0.isDayOf == isDayOf && !$0.isPacked }.count
    }

    func getCompleteItems(for itemType: ListType) -> Int {
        return allItems.filter { $0.type == itemType && $0.isPacked }.count
    }

    func getCompleteItems(for itemType: ListType, isDayOf: Bool) -> Int {
        return allItems.filter { $0.type == itemType && $0.isDayOf == isDayOf && $0.isPacked }.count
    }

    func allItemsComplete(for itemType: ListType) -> Bool {
        return self.getTotalItems(for: itemType) == self.getCompleteItems(for: itemType)
    }

    // MARK: Get Lists
    func getLists(for listType: ListType) -> [PackingList] {
        return self.lists?.filter { $0.type == listType } ?? []
    }

    func getLists(for listType: ListType, isDayOf: Bool) -> [PackingList] {
        return self.lists?.filter { $0.type == listType && $0.isDayOf == isDayOf } ?? []
    }

    func getLists(for user: User?) -> [PackingList] {
        return self.lists ?? []
    }

    func getLists(for user: User?, ofType listType: ListType) -> [PackingList] {
        return self.getLists(for: listType)
    }

    func getLists(for user: User?, ofType listType: ListType, isDayOf: Bool) -> [PackingList] {
        return self.getLists(for: listType, isDayOf: isDayOf)
    }

    // MARK: CRUD Lists
    func addList(_ list: PackingList) {
        if self.lists == nil {
            self.lists = []
        }
        self.lists!.append(list)
    }

    func removeList(_ listToRemove: PackingList) -> Bool {
        guard var lists = self.lists,
              let index = lists.firstIndex(of: listToRemove) else {
            AppLogger.trip.warning("Could not find list \(listToRemove.name) in trip \(self.name)")
            return false
        }
        AppLogger.trip.debug("Removing \(listToRemove.name) from lists of \(self.name)")
        lists.remove(at: index)
        self.lists = lists
        return true
    }

    func applyDefaultLists(to user: User?, lists: [PackingList], in context: ModelContext) {
        if !lists.isEmpty {
            for list in lists {
                let defaultList = PackingList.copy(list, for: self, with: user)
                context.insert(defaultList)
                self.addList(defaultList)
            }
            try? context.save()
        }
    }
}

extension Trip {
    /// Duration of trip in number of days
    var duration: Int {
        return Calendar.current.numberOfDaysBetween(self.startDate, and: self.endDate)
    }

    var daysUntilDeparture: Int {
        if self.status == .upcoming {
            return Calendar.current.numberOfDaysBetween(.now, and: self.startDate)
        } else {
            return 0
        }
    }

    var daysUntilReturn: Int {
        if self.status == .active {
            return Calendar.current.numberOfDaysBetween(.now, and: self.endDate)
        } else {
            return 0
        }
    }
}

extension Trip {
    static var sampleTrip = Trip(name: "Anniversary Trip", startDate: Date(), endDate: Date.now.addingTimeInterval(86400), type: .plane, origin: TripLocation.sampleOrigin, destination: TripLocation.sampleDestination, accomodation: .hotel)
}

/// Notification Code
extension Trip {
    func createDayOfPackingNotification() {
        guard FeatureFlags.shared.showingNotifications else { return }

        NotificationUtilities.getNotificationPermission()

        // Create the content
        let content = UNMutableNotificationContent()
        content.title = "Check your packing lists!"
        content.body = "You have \(self.totalIncompletePackingItemsEntries) items to pack before you head out."

        // Configure the date
        var components = Calendar.current.dateComponents([.day, .month, .year], from: self.startDate)
        components.hour = 8

        // Create the trigger as a one-time event.
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        // Create the request
        self.dayOfNotificationUUID = UUID().uuidString
        let request = UNNotificationRequest(identifier: self.dayOfNotificationUUID!,
                                            content: content, trigger: trigger)


        // Schedule the request with the system.
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.add(request) { (error) in
            if error != nil {
                // Handle any errors.
            }
        }
    }
}
