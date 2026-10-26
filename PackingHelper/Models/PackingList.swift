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

/// What a list holds. Packing lists check items off as packed, task lists as done.
/// Either kind can also be a day-of list (`PackingList.isDayOf`): things you can't
/// pack or do ahead, for the day you leave.
enum ListKind: String, Codable, CaseIterable, Identifiable {
    case packing, tasks

    var id: String { rawValue }

    var name: String {
        switch self {
        case .packing: "Packing"
        case .tasks: "Tasks"
        }
    }

    /// Past tense for checked items: "Packed" or "Done"
    var checkedWord: String {
        self == .packing ? "Packed" : "Done"
    }

    /// SF Symbol for this kind, for pickers and filters
    var image: Image {
        switch self {
        case .packing: Image(systemName: suitcaseIcon)
        case .tasks: Image(systemName: "checklist")
        }
    }

    /// Glyph shown before a list's name. nil for everyday packing lists,
    /// so trips with only packing lists look unchanged.
    func glyph(isDayOf: Bool) -> Image? {
        switch (self, isDayOf) {
        case (.packing, false): nil
        case (.tasks, false): Image(systemName: "checklist")
        case (.packing, true): Image(suitcaseDayOfIcon)
        case (.tasks, true): Image(checklistDayOfIcon)
        }
    }

    /// "Tasks", "Day Of", or "Day Of Tasks", for VoiceOver and info rows
    func displayName(isDayOf: Bool) -> String {
        switch (self, isDayOf) {
        case (_, false): name
        case (.packing, true): "Day Of"
        case (.tasks, true): "Day Of Tasks"
        }
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

    // Stored as a raw string: lightweight migration fills existing rows with this default,
    // where a Codable enum attribute comes back empty and crashes on read
    var kindRawValue: String = ListKind.packing.rawValue

    var kind: ListKind {
        get { ListKind(rawValue: kindRawValue) ?? .packing }
        set { kindRawValue = newValue.rawValue }
    }

    /// For the day you leave: stays at the end of the trip's lists and feeds the
    /// trip detail "left for today" line. The Default list is never day-of.
    var isDayOf: Bool = false

    var name: String = "List"

    // Unique identifier for drag-and-drop transfers
    var uuid: UUID = UUID()

    // Legacy template variables (template system still uses these)
    var template: Bool = false
    var countAsDays: Bool = false
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

    init(kind: ListKind = .packing, isDayOf: Bool = false, template: Bool, name: String, countAsDays: Bool, sortOrder: Int = 0) {
        self.created = Date.now
        self.kindRawValue = kind.rawValue
        self.isDayOf = isDayOf
        self.template = template
        self.items = []
        self.appliedToLists = []
        self.name = name
        self.countAsDays = countAsDays
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
}

extension PackingList {
    /// Glyph before the list's name; nil for everyday packing lists
    var glyph: Image? { kind.glyph(isDayOf: isDayOf) }
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
}

extension PackingList {
    @discardableResult
    static func save(
        _ packingList: PackingList?,
        name: String,
        template: Bool,
        kind: ListKind? = nil,
        isDayOf: Bool? = nil,
        owner: User? = nil,
        in context: ModelContext,
        for trip: Trip?
    ) -> PackingList? {
        AppLogger.packingList.info("Saving packing list...")
        if let packingList {
            AppLogger.packingList.debug("Packing list already exists. Updating with new info.")
            packingList.name = name
            // The Default list stays an everyday packing list
            if !packingList.isDefault {
                if let kind { packingList.kind = kind }
                if let isDayOf { packingList.isDayOf = isDayOf }
            }
            if packingList.template {
                packingList.user = owner
            }
        } else {
            AppLogger.packingList.debug("Packing list does not already exist. Creating with new info.")
            let newPackingList = PackingList(kind: kind ?? .packing, isDayOf: isDayOf ?? false, template: template, name: name, countAsDays: false)
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
        let newList = PackingList(kind: packingList.kind, isDayOf: packingList.isDayOf, template: packingList.template, name: packingList.name, countAsDays: packingList.countAsDays)
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

    /// Supplies the name and category for the template copy
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

    /// A trip list made on the trip (not applied from a template) that could be saved as a new
    /// template. The Default list is left out ("Default" can't be a template name), as are empty lists.
    var isNewTemplateCandidate: Bool {
        !template && appliedFromTemplate == nil && !isDefault && !(items ?? []).isEmpty
    }

    /// Whether a template with this name already exists (saving anyway makes a second one)
    static func templateNameExists(_ name: String, in templates: [PackingList]) -> Bool {
        let key = name.itemMatchKey
        return !key.isEmpty && templates.contains { $0.template && $0.name.itemMatchKey == key }
    }

    /// Saves this trip list as a new template: item names and counts only (unpacked, no packer).
    /// Links this list to it, so later additions show up in trip review like any template's.
    @discardableResult
    func saveAsNewTemplate(named name: String, owner: User?, in context: ModelContext) -> PackingList {
        let template = PackingList(
            kind: kind,
            isDayOf: isDayOf,
            template: true,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            countAsDays: false
        )
        context.insert(template)
        template.user = owner

        let sourceItems = Item.sorted(items ?? [], sortOrder: .byCustomOrder)
        for (order, item) in sourceItems.enumerated() {
            let templateItem = Item(
                name: item.name.trimmingCharacters(in: .whitespacesAndNewlines),
                category: item.category,
                count: item.count,
                isPacked: false,
                sortOrder: order
            )
            context.insert(templateItem)
            templateItem.list = template
        }

        appliedFromTemplate = template
        AppLogger.packingList.info("Saved trip list \(self.name) as new template \(template.name)")
        return template
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
                sortOrder: nextSortOrder
            )
            context.insert(templateItem)
            templateItem.list = source
            nextSortOrder += 1
            AppLogger.packingList.info("Saved \(templateItem.name) back to template \(source.name)")
        }
    }
}
