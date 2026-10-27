//
//  Item.swift
//  PackingHelper
//
//  Created by Todd Louison on 10/22/23.
//

import Foundation
import SwiftData

@Model
class Item {
    var name: String = "Item"
    var list: PackingList?
    var count: Int = 1
    var category: String = "Clothing"
    var isPacked: Bool = false

    var created: Date = Date.now
    var uuid: UUID = UUID()

    // Sort order within a section (PackingList)
    var sortOrder: Int = 0

    // The packer
    @Relationship var user: User?

    // Legacy: retained so the v2 migration can read it; new code uses sortOrder only
    var unifiedSortOrder: Int = 0

    init(name: String, category: String, count: Int, isPacked: Bool, sortOrder: Int = 0) {
        self.name = name
        self.count = count
        self.category = category
        self.isPacked = isPacked
        self.sortOrder = sortOrder
    }

    static func copy(_ item: Item) -> Item {
        let copyItem = Item(
            name: item.name,
            category: item.category,
            count: item.count,
            isPacked: item.isPacked,
            sortOrder: item.sortOrder
        )
        copyItem.list = item.list
        copyItem.user = item.user
        return copyItem
    }

    static func copyForTemplate(_ item: Item) -> Item {
        let copyItem = Item(
            name: item.name,
            category: item.category,
            count: item.count,
            isPacked: false,
            sortOrder: item.sortOrder
        )
        copyItem.list = item.list
        // Templates are generic — user assignment is not carried over
        return copyItem
    }

    /// Inserts an unpacked, unassigned copy of `item` (trimmed name) into a template list
    @discardableResult
    static func insertTemplateItem(from item: Item, count: Int, sortOrder: Int, into template: PackingList, in context: ModelContext) -> Item {
        let templateItem = Item(
            name: item.name.trimmingCharacters(in: .whitespacesAndNewlines),
            category: item.category,
            count: count,
            isPacked: false,
            sortOrder: sortOrder
        )
        context.insert(templateItem)
        templateItem.list = template
        return templateItem
    }

    static func create(
        for list: PackingList,
        in context: ModelContext,
        category: PackingRecommendationCategory?,
        name: String,
        count: Int,
        isPacked: Bool,
        user: User? = nil
    ) {
        var itemCategory = category
        if list.kind == .tasks {
            itemCategory = .Task
        } else if itemCategory == nil {
            itemCategory = PackingEngine.interpretItem(itemName: name)
        }

        let newItem = Item(
            name: name,
            category: (itemCategory ?? .other).rawValue.capitalized,
            count: count,
            isPacked: isPacked
        )
        newItem.user = user
        newItem.list = list

        list.addItem(newItem)
        context.insert(newItem)
    }

    static func sorted(_ items: [Item], sortOrder: ItemSortOrder = .byDate) -> [Item] {
        switch sortOrder {
        case .byNameAsc:
            return items.sorted { $0.name < $1.name }
        case .byNameDesc:
            return items.sorted { $0.name > $1.name }
        case .byUser:
            return items.sorted { lhs, rhs in
                switch (lhs.user, rhs.user) {
                case (nil, nil): return false
                case (nil, _): return true
                case (_, nil): return false
                case let (l?, r?): return l.name < r.name
                }
            }
        case .byDate:
            return items.sorted { $0.created < $1.created }
        case .byCustomOrder:
            return items.sorted { $0.sortOrder < $1.sortOrder }
        }
    }
}

enum ItemSortOrder: String, SortOrderOption {
    case byDate, byUser, byNameAsc, byNameDesc, byCustomOrder

    var name: String {
        if case .byCustomOrder = self {
            return "Manual Order"
        }
        return BaseSortOrder(rawValue: rawValue)?.name ?? ""
    }

    var id: String { rawValue }

    var `default`: String {
        BaseSortOrder.byDate.rawValue
    }
}
