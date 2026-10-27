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
        case .family: "With Family"
        case .friend: "With Friends"
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
    /// The saved AI assistant chat, if one was started
    @Relationship(deleteRule: .cascade, inverse: \AIConversation.trip) var aiConversation: AIConversation?

    var startDate: Date = Date.now
    var endDate: Date = Date.now.advanced(by: SECONDS_IN_DAY)
    var createdDate: Date = Date.now

    /// How the trip gets there; several allowed, kept in `allCases` order
    var types: [TripType] = [TripType.plane]
    /// Where the trip stays; several allowed, kept in `allCases` order
    var accomodations: [TripAccomodation] = [TripAccomodation.hotel]

    var dayOfNotificationUUID: String?

    /// Set when the user saves from or dismisses the post-trip template review card
    var templateReviewDismissed: Bool = false

    init(name: String, startDate: Date, endDate: Date, types: [TripType], origin: TripLocation?, destination: TripLocation, accomodations: [TripAccomodation]) {
        self.createdDate = Date.now

        self.name = name

        self.startDate = startDate
        self.endDate = endDate

        self.types = types
        self.accomodations = accomodations

        self.origin = origin
        self.destination = destination

        if FeatureFlags.notificationsEnabled {
            self.createDayOfPackingNotification()
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

    /// The transport whose icon stands for the trip: the first selected, plane if none
    var primaryType: TripType {
        types.first ?? .plane
    }

    /// Selected transport names, e.g. "Plane, Car"
    var typesName: String {
        types.isEmpty ? TripType.plane.name : types.map(\.name).joined(separator: ", ")
    }

    /// Selected accommodation names, e.g. "Hotel, With Family"
    var accomodationsName: String {
        accomodations.map(\.name).joined(separator: ", ")
    }

    @ViewBuilder
    func getTypeLabel() -> some View {
        switch self.status {
        case .returning, .complete:
            primaryType.endLabel(text: typesName)
        default:
            primaryType.startLabel(text: typesName)
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
    /// Total and packed counts in one walk over the lists, without building the flattened array
    var itemCounts: (total: Int, packed: Int) {
        var total = 0
        var packed = 0
        for list in lists ?? [] {
            for item in list.items ?? [] {
                total += 1
                if item.isPacked { packed += 1 }
            }
        }
        return (total, packed)
    }

    var totalItemsCount: Int { itemCounts.total }
    var packedItemsCount: Int { itemCounts.packed }
    var incompleteItemsCount: Int {
        let counts = itemCounts
        return counts.total - counts.packed
    }

    // MARK: Default list accessors
    var defaultPackingList: PackingList? {
        lists?.first(where: { $0.isDefault })
    }

    var hasDefaultLists: Bool {
        defaultPackingList != nil
    }

    // MARK: List metadata (item-based)
    var packers: [User] {
        var users = Set<User>()
        for list in lists ?? [] {
            for item in list.items ?? [] {
                if let user = item.user { users.insert(user) }
            }
        }
        return Array(users)
    }

    var listsFromTemplates: [PackingList] {
        return self.lists?.filter { $0.appliedFromTemplate != nil } ?? []
    }

    var alreadyUsedTemplates: [PackingList] {
        return self.listsFromTemplates.compactMap { $0.appliedFromTemplate }
    }

    /// Template sections with items that could be saved back to their template, in section order
    var templateCandidateSections: [PackingList] {
        PackingList.sorted(listsFromTemplates, sortOrder: .byCustomOrder)
            .filter { !$0.templateCandidates.isEmpty }
    }

    var templateCandidateCount: Int {
        listsFromTemplates.reduce(0) { $0 + $1.templateCandidates.count }
    }

    /// Lists made on this trip that could be saved as new templates, in section order
    var newTemplateCandidateLists: [PackingList] {
        PackingList.sorted(lists ?? [], sortOrder: .byCustomOrder)
            .filter(\.isNewTemplateCandidate)
    }

    var showsTemplateReviewCard: Bool {
        status == .complete && !templateReviewDismissed
            && (templateCandidateCount > 0 || !newTemplateCandidateLists.isEmpty)
    }

    /// Items plus new lists waiting in trip review, for badges
    var templateReviewCount: Int {
        templateCandidateCount + newTemplateCandidateLists.count
    }

    /// "3 new items and 1 new list", for the review prompts
    var templateReviewSummary: String {
        let itemCount = templateCandidateCount
        let listCount = newTemplateCandidateLists.count
        var parts: [String] = []
        if itemCount > 0 { parts.append(itemCount == 1 ? "1 new item" : "\(itemCount) new items") }
        if listCount > 0 { parts.append(listCount == 1 ? "1 new list" : "\(listCount) new lists") }
        return parts.joined(separator: " and ")
    }

    // MARK: Get Lists
    func sortedLists(of kind: ListKind) -> [PackingList] {
        PackingList.sorted(lists ?? [], sortOrder: .byCustomOrder).filter { $0.kind == kind }
    }

    var dayOfLists: [PackingList] {
        PackingList.sorted(lists ?? [], sortOrder: .byCustomOrder).filter(\.isDayOf)
    }

    // MARK: CRUD Lists
    func addList(_ list: PackingList) {
        if self.lists == nil {
            self.lists = []
        }
        // New sections go last; the Default section keeps its -1 so it stays first.
        // Day-of lists stay at the end: other new lists go in front of them.
        if !list.isDefault {
            let dayOfLists = self.dayOfLists
            if !list.isDayOf, let firstDayOf = dayOfLists.first {
                list.sortOrder = firstDayOf.sortOrder
                for dayOfList in dayOfLists { dayOfList.sortOrder += 1 }
            } else {
                list.sortOrder = SortOrderManager.nextListSortOrder(in: self.lists!)
            }
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

/// Notification Code
extension Trip {
    func createDayOfPackingNotification() {
        guard FeatureFlags.notificationsEnabled else { return }

        NotificationUtilities.getNotificationPermission()

        // Create the content
        let content = UNMutableNotificationContent()
        content.title = "Check your packing lists!"
        content.body = "You have \(self.incompleteItemsCount) items to pack before you head out."

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
            if let error {
                AppLogger.notifications.error("Failed to schedule day-of notification: \(error.localizedDescription)")
            }
        }
    }
}
