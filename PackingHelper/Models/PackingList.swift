//
//  PackingList.swift
//  PackingHelper
//
//  Created by Todd Louison on 10/13/23.
//

import Foundation
import SwiftUI
import SwiftData
import OSLog

enum ListType: String, CaseIterable, Comparable {
    case packing="Packing", task="Task"

    private var sortOrder: Int {
        switch self {
            case .packing:
                return 0
            case .task:
                return 1
        }
    }

    var icon: String {
        switch self {
            case .packing: suitcaseIcon
            case .task: "checklist"
        }
    }

    var localizedDisplayName: String {
        switch self {
        case .packing: return "Packing"
        case .task: return "Task"
        }
    }

    static func ==(lhs: ListType, rhs: ListType) -> Bool {
            return lhs.sortOrder == rhs.sortOrder
    }

    static func <(lhs: ListType, rhs: ListType) -> Bool {
       return lhs.sortOrder < rhs.sortOrder
    }
}

// Custom Codable implementation to handle legacy "Day-of" value
extension ListType: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        // Handle legacy "Day-of" value by mapping to packing
        if rawValue == "Day-of" {
            self = .packing
        } else if let listType = ListType(rawValue: rawValue) {
            self = listType
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Cannot initialize ListType from invalid String value \(rawValue)"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}

// PackingList sort order
enum PackingListSortOrder: String, SortOrderOption {
    case byDate, byUser, byNameAsc, byNameDesc, byCustomOrder

    var name: String {
        if case .byCustomOrder = self {
            return "Manual Order"
        }
        return BaseSortOrder(rawValue: rawValue)?.name ?? ""
    }

    var id: String { rawValue }

    var `default`: String {
        BaseSortOrder.byDate.name
    }
}

@Model
final class PackingList {
    var created: Date = Date.now

    // Legacy: type/user/isDayOf are now stored on Item; kept for migration reads
    var type: ListType = ListType.packing
    var typeString: String {
        type.rawValue
    }

    var name: String = "List"

    // Unique identifier for drag-and-drop transfers
    var uuid: UUID = UUID()

    // Legacy template variables (template system still uses these)
    var template: Bool = false
    var countAsDays: Bool = false
    var isDayOf: Bool = false
    var appliedFromTemplate: PackingList? = nil
    @Relationship(deleteRule: .nullify, inverse: \PackingList.appliedFromTemplate) var appliedToLists: [PackingList]?

    // Sort order for section ordering in the packing view
    var sortOrder: Int = 0

    // Whether this is a protected default catch-all section (undeletable, name-locked)
    var isDefault: Bool = false

    // Template owner. Unused for trip lists (users live on items; legacy values kept for migration reads)
    var user: User?
    var trip: Trip?

    @Relationship(deleteRule: .cascade, inverse: \Item.list) var items: [Item]?

    init(type: ListType = .packing, template: Bool, name: String, countAsDays: Bool, isDayOf: Bool = false, sortOrder: Int = 0) {
        self.created = Date.now
        self.type = type
        self.template = template
        self.items = []
        self.appliedToLists = []
        self.name = name
        self.countAsDays = countAsDays
        self.isDayOf = isDayOf
        self.sortOrder = sortOrder
    }

    var incompleteItems: [Item] {
        self.items?.filter{ $0.isPacked == false } ?? []
    }
    var completeItems: [Item] {
        self.items?.filter{ $0.isPacked == true } ?? []
    }
    var totalItems: Int {
        self.items?.count ?? 0
    }

    func addItem(_ item: Item) {
        if self.items == nil {
            self.items = []
        }
        self.items!.append(item)
    }

    func removeItem(_ item: Item) {
        guard let index = items?.firstIndex(of: item) else { return }
        AppLogger.packingList.debug("Removing item \(item.name)")
        items?.remove(at: index)
    }

    func removeItem(at index: Int) {
        if self.items != nil {
            AppLogger.packingList.debug("Removing item at index \(index)")
            self.items?.remove(at: index)
        }
    }

    var icon: String {
        return "list.bullet"
    }

    @ViewBuilder
    var iconImage: some View {
        Image(systemName: "list.bullet")
    }

    static func icon(listType: ListType, isDayOf: Bool = false) -> String {
        if isDayOf {
            return switch listType {
                case .packing: suitcaseDayOfIcon
                case .task: checklistDayOfIcon
            }
        }
        return switch listType {
            case .packing: suitcaseIcon
            case .task: "checklist"
        }
    }

    @ViewBuilder
    static func iconImage(listType: ListType, isDayOf: Bool = false) -> some View {
        if isDayOf {
            switch listType {
            case .packing:
                Image(suitcaseDayOfIcon)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.yellow, Color.accentColor, Color.white)
            case .task:
                Image(checklistDayOfIcon)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.yellow, Color.accentColor, Color.white)
            }
        } else {
            switch listType {
            case .packing: Image(systemName: suitcaseIcon)
            case .task: Image(systemName: "checklist")
            }
        }
    }
}

extension PackingList {
    static let defaultListName = "Default"

    static func isReservedName(_ name: String) -> Bool {
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == defaultListName.lowercased()
    }

    // Creates a single default catch-all section for a trip (v2 model)
    @discardableResult
    static func createDefaultList(for trip: Trip, in context: ModelContext) -> PackingList {
        let list = PackingList(template: false, name: defaultListName, countAsDays: false, sortOrder: -1)
        list.isDefault = true
        context.insert(list)
        trip.addList(list)
        return list
    }

    // Legacy overload kept for migration code; demoted = no longer creates default packing/task pairs
    @discardableResult
    static func createDefaultList(for trip: Trip, user: User, type: ListType, in context: ModelContext) -> PackingList {
        let list = PackingList(type: type, template: false, name: defaultListName, countAsDays: false, sortOrder: -1)
        list.isDefault = true
        list.user = user
        context.insert(list)
        trip.addList(list)
        return list
    }
}

extension PackingList {
    @discardableResult
    static func save(
        _ packingList: PackingList?,
        name: String,
        template: Bool,
        owner: User? = nil,
        in context: ModelContext,
        for trip: Trip?
    ) -> PackingList? {
        AppLogger.packingList.info("Saving packing list...")
        if let packingList {
            AppLogger.packingList.debug("Packing list already exists. Updating with new info.")
            packingList.name = name
            if packingList.template {
                packingList.user = owner
            }
        } else {
            AppLogger.packingList.debug("Packing list does not already exist. Creating with new info.")
            let newPackingList = PackingList(template: template, name: name, countAsDays: false)
            if template {
                newPackingList.user = owner
            }

            context.insert(newPackingList)

            if let trip {
                AppLogger.packingList.debug("New list belongs to trip, applying to trip's lists.")
                trip.addList(newPackingList)
            }

            do {
                try context.save()
                AppLogger.packingList.info("Packing list saved!")
            } catch {
                AppLogger.packingList.error("Failed to save packing list: \(error.localizedDescription)")
            }

            return newPackingList
        }

        do {
            try context.save()
            AppLogger.packingList.info("Packing list saved!")
        } catch {
            AppLogger.packingList.error("Failed to save packing list: \(error.localizedDescription)")
        }

        return nil
    }

    static func delete(_ packingList: PackingList, from context: ModelContext) {
        let list_name = packingList.name
        AppLogger.packingList.info("Deleting \(list_name)")

        if let trip = packingList.trip {
            AppLogger.packingList.info("Removing \(list_name) from trip \(trip.name)")
            _ = trip.removeList(packingList)
        }

        context.delete(packingList)
        do {
            try context.save()
            AppLogger.packingList.info("Successfully deleted \(list_name)")
        } catch {
            AppLogger.packingList.error("Failed to delete packing list: \(error.localizedDescription)")
        }
    }
}

extension PackingList {
    static func filtered(user: User?, _ lists: [PackingList]) -> [PackingList] {
        // User filtering is now at the item level; return all lists
        return lists
    }

    static func sorted(_ lists: [PackingList], sortOrder: PackingListSortOrder = .byDate) -> [PackingList] {
        switch sortOrder {
            case .byNameAsc:
                return lists.sorted { $0.name < $1.name }
            case .byNameDesc:
                return lists.sorted { $0.name > $1.name}
            case .byUser:
                return lists.sorted { $0.name < $1.name }
            case .byDate:
                return lists.sorted { $0.created < $1.created }
            case .byCustomOrder:
                return lists.sorted { $0.sortOrder < $1.sortOrder }
            }
    }

    static func containsMultiplePackers(_ lists: [PackingList]) -> Bool {
        let allItems = lists.flatMap { $0.items ?? [] }
        return Set(allItems.compactMap { $0.user?.persistentModelID }).count > 1
    }
}

extension PackingList {
    var appliedTrips: [Trip] {
        let applied = appliedToLists ?? []
        var seen = Set<PersistentIdentifier>()
        var unique: [Trip] = []
        for list in applied {
            if let trip = list.trip, seen.insert(trip.persistentModelID).inserted {
                unique.append(trip)
            }
        }
        return unique
    }

    var lastUpdatedDate: Date? {
        items?.compactMap { $0.created }.max()
    }

    var lastAppliedTrip: Trip? {
        appliedTrips.max(by: { $0.startDate < $1.startDate })
    }
}

extension PackingList {
    static func samplePackingList() -> PackingList {
        return PackingList(template: false, name: "Packing List", countAsDays: false)
    }

    static func sampleDefaultList() -> PackingList {
        return PackingList(template: true, name: "Template List", countAsDays: false)
    }
}

extension PackingList {
    private static func _copy(_ packingList: PackingList, for trip: Trip? = nil, template: Bool = false) -> PackingList {
        let newList = PackingList(template: packingList.template, name: packingList.name, countAsDays: packingList.countAsDays)
        AppLogger.packingList.info("Copied list.")

        if let items = packingList.items {
            AppLogger.packingList.info("Original list contained items, copying items to new list.")
            for item in items {
                let newItem: Item
                if template {
                    newItem = Item.copyForTemplate(item)
                } else {
                    newItem = Item.copy(item)
                }
                // Scale count to trip duration if countAsDays was set
                if !template && packingList.countAsDays {
                    let itemCount = trip?.duration ?? newItem.count
                    AppLogger.packingList.info("Original list is marked as 'countAsDays=true', setting item count to \(itemCount)")
                    newItem.count = itemCount
                }

                newList.items?.append(newItem)
            }
        }

        return newList
    }

    static func copy(_ list: PackingList, for trip: Trip) -> PackingList {
        AppLogger.packingList.info("Copying packing list \(list.name) to apply to a trip.")
        let newList = PackingList._copy(list, for: trip, template: false)
        newList.template = false

        // Note what template this was created from
        if list.template {
            newList.appliedFromTemplate = list
        }

        return newList
    }

    static func copy(_ list: PackingList, for trip: Trip, with user: User?) -> PackingList {
        let newList = PackingList.copy(list, for: trip)
        // An owned template's items always go to its owner; the chosen packer only applies to shared templates
        let owner = list.template ? list.user : nil
        if let user = owner ?? user {
            AppLogger.packingList.info("Copied packing list \(list.name) to apply to a trip for user \(user.name).")
            // Assign user to all copied items (not the list itself)
            newList.items?.forEach { $0.user = user }
        }
        return newList
    }
}

// MARK: - Saving trip items back to templates

extension String {
    /// Key for "same item" comparisons between trip lists and templates
    var itemMatchKey: String {
        lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

/// Trip items sharing a name that aren't in the template their section was applied from
struct TemplateCandidate: Identifiable {
    let key: String
    /// Every trip item in the group, oldest first
    let items: [Item]

    var id: String { key }

    /// Supplies the name, category and type for the template copy
    var displayItem: Item { items[0] }
}

extension PackingList {
    /// Normalized names of this list's items
    var itemMatchKeys: Set<String> {
        Set((items ?? []).map(\.name.itemMatchKey))
    }

    /// Whether an item in this trip section may be saved back to its template:
    /// only the template owner's items, or unassigned ones (any item if the template has no owner)
    func isTemplateEligible(_ item: Item) -> Bool {
        guard let source = appliedFromTemplate else { return false }
        guard let owner = source.user, let user = item.user else { return true }
        return user.persistentModelID == owner.persistentModelID
    }

    /// Eligible items not present in the source template, grouped by name.
    /// Empty when this isn't a trip section applied from a template.
    var templateCandidates: [TemplateCandidate] {
        guard !template, let source = appliedFromTemplate else { return [] }
        let templateKeys = source.itemMatchKeys
        let eligible = (items ?? []).filter { item in
            let key = item.name.itemMatchKey
            return !key.isEmpty && !templateKeys.contains(key) && isTemplateEligible(item)
        }
        return Dictionary(grouping: eligible) { $0.name.itemMatchKey }
            .map { key, items in
                TemplateCandidate(key: key, items: items.sorted { $0.created < $1.created })
            }
            .sorted { lhs, rhs in
                (lhs.displayItem.sortOrder, lhs.displayItem.created) < (rhs.displayItem.sortOrder, rhs.displayItem.created)
            }
    }

    /// Adds one item per candidate to the template this section was applied from
    func saveToTemplate(_ candidates: [TemplateCandidate], in context: ModelContext) {
        guard let source = appliedFromTemplate else { return }
        // Re-checked here so double taps or a stale review sheet can't add duplicates
        var existingKeys = source.itemMatchKeys
        var nextSortOrder = (source.items?.map(\.sortOrder).max() ?? -1) + 1

        for candidate in candidates where existingKeys.insert(candidate.key).inserted {
            let item = candidate.displayItem
            // Templates store base counts and aren't assigned to a packer
            let templateItem = Item(
                name: item.name.trimmingCharacters(in: .whitespacesAndNewlines),
                category: item.category,
                count: 1,
                isPacked: false,
                sortOrder: nextSortOrder,
                type: item.type,
                isDayOf: item.isDayOf
            )
            context.insert(templateItem)
            templateItem.list = source
            nextSortOrder += 1
            AppLogger.packingList.info("Saved \(templateItem.name) back to template \(source.name)")
        }
    }
}
