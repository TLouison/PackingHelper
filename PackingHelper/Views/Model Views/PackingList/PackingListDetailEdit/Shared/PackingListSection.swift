//
//  PackingListSection.swift
//  PackingHelper
//
//  Created by Claude on 1/11/26.
//

import SwiftUI
import SwiftData

struct PackingListSection: View {
    @Environment(\.modelContext) private var modelContext

    let packingList: PackingList
    let users: [User]?
    @Binding var isExpanded: Bool
    @Binding var editingItemId: PersistentIdentifier?

    // Item-level filters (applied within each section)
    var selectedUser: User? = nil
    var selectedType: ListType? = nil
    var showDayOfOnly: Bool = false

    let onTogglePacked: (Item) -> Void
    let onUpdateItem: (Item, String, Int) -> Void
    let onDeleteItem: (Item) -> Void
    let onEditList: () -> Void
    let onDeleteList: () -> Void
    let onSaveAsDefault: () -> Void
    let onItemReorder: (Item, PackingList, Int) -> Void
    let onCrossListDrop: (Item, PackingList, Int) -> Void
    let onAddItemToList: (PackingList) -> Void
    /// Items that aren't in their section's template yet
    var templateCandidateIDs: Set<PersistentIdentifier> = []
    var onAddToTemplate: ((Item) -> Void)? = nil
    var onUpdateTemplate: (() -> Void)? = nil
    var isReorderMode: Bool = false

    /// Keeps just-packed items in place briefly before they move to the packed section
    let pendingPacks: PendingPackTracker

    // Inline new item row
    var isAddingNewItem: Bool = false
    var targetList: PackingList? = nil
    @Binding var newItemName: String
    @Binding var newItemFieldFocused: Bool
    var newItemCount: Int = 1
    let onSubmitNewItem: () -> Void
    let onTapEmptyArea: (PackingList) -> Void

    private var unpackedItems: [Item] {
        var items = pendingPacks.visibleUnpacked(packingList.items ?? [])
        if let user = selectedUser {
            items = items.filter { $0.user?.persistentModelID == user.persistentModelID }
        }
        if let type = selectedType {
            items = items.filter { $0.type == type }
        }
        if showDayOfOnly {
            items = items.filter { $0.isDayOf }
        }
        return Item.sorted(items, sortOrder: .byCustomOrder)
    }

    private var isTargetList: Bool {
        isAddingNewItem && targetList?.persistentModelID == packingList.persistentModelID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Section header
            PackingListSectionHeader(
                packingList: packingList,
                isExpanded: $isExpanded,
                onAddItem: {
                    withAnimation { isExpanded = true }
                    onAddItemToList(packingList)
                },
                onEditList: onEditList,
                onDeleteList: onDeleteList,
                onSaveAsDefault: onSaveAsDefault,
                onUpdateTemplate: onUpdateTemplate,
                isReorderMode: isReorderMode
            )

            if !isReorderMode && isExpanded {
                // Unpacked items
                if !unpackedItems.isEmpty {
                    ReorderableItemsSection(
                        items: unpackedItems,
                        isTemplating: false,
                        targetList: packingList,
                        editingItemId: $editingItemId,
                        onTogglePacked: onTogglePacked,
                        onUpdateItem: onUpdateItem,
                        onDeleteItem: onDeleteItem,
                        onReorder: { item, index in
                            onItemReorder(item, packingList, index)
                        },
                        onCrossListMove: onCrossListDrop,
                        templateCandidateIDs: templateCandidateIDs,
                        onAddToTemplate: onAddToTemplate
                    )
                    .padding(.horizontal, 8)
                }

                // Inline new item row, or a blank area that starts one when tapped
                if isTargetList {
                    NewItemRow(
                        itemName: $newItemName,
                        isFocused: $newItemFieldFocused,
                        itemCount: newItemCount,
                        onSubmitReturn: onSubmitNewItem,
                        onDeleteEmpty: {
                            // Backspace on the empty new row moves editing up to the last item
                            if let lastItem = unpackedItems.last {
                                editingItemId = lastItem.persistentModelID
                            }
                        }
                    )
                    .padding(.horizontal, 8)
                    .id(NewItemRow.scrollID(for: packingList))
                } else {
                    AddItemTapZone(showsEmptyHint: unpackedItems.isEmpty) {
                        onTapEmptyArea(packingList)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}
