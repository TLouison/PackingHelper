//
//  ReorderableItemsSection.swift
//  PackingHelper
//
//  Reusable component for drag-and-drop item reordering
//

import SwiftData
import SwiftUI

struct ReorderableItemsSection: View {
    let items: [Item]

    @Binding var editingItemId: PersistentIdentifier?
    let onUpdateItem: (Item, String, Int) -> Void
    let onDeleteItem: (Item) -> Void
    let onReorder: (Item, Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Drop zone at top
            ItemDropZone(insertionIndex: 0) { droppedItem in
                onReorder(droppedItem, 0)
            }

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if editingItemId == item.persistentModelID {
                    EditableItemRow(
                        item: item,
                        onCommit: { name, count in
                            onUpdateItem(item, name, count)
                        },
                        onCancel: {
                            // Only clear if another row hasn't already taken over editing
                            if editingItemId == item.persistentModelID { editingItemId = nil }
                        },
                        onDeleteEmpty: {
                            // Reminders-style: backspace on empty deletes and moves editing up a row
                            let previousItem = index > 0 ? items[index - 1] : nil
                            onDeleteItem(item)
                            editingItemId = previousItem?.persistentModelID
                        }
                    )
                } else {
                    UnifiedItemRow(
                        item: item,
                        onEdit: { editingItemId = item.persistentModelID },
                        onDelete: { onDeleteItem(item) }
                    )
                    .draggable(ItemTransferData(item: item)) {
                        // Drag preview
                        UnifiedItemRow(
                            item: item,
                            onEdit: {},
                            onDelete: {}
                        ).rowContent
                    }
                }

                // Drop zone after each item
                ItemDropZone(insertionIndex: index + 1) { droppedItem in
                    onReorder(droppedItem, index + 1)
                }
            }
        }
    }
}

// MARK: - Drop Zone Component

struct ItemDropZone: View {
    let insertionIndex: Int
    let onDrop: (Item) -> Void

    @State private var isTargeted = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Rectangle()
            .fill(isTargeted ? Color.blue.opacity(0.3) : Color.clear)
            .frame(height: isTargeted ? 40 : 8)
            .clipShape(.rect(cornerRadius: 8))
            .padding(.vertical, isTargeted ? 4 : 0)
            .contentShape(Rectangle())
            .dropDestination(for: ItemTransferData.self) { items, location in
                guard let transferData = items.first else { return false }

                // Look up the item from the model context using UUID
                let descriptor = FetchDescriptor<Item>(
                    predicate: #Predicate<Item> { item in
                        item.uuid == transferData.itemUUID
                    }
                )

                if let allItems = try? modelContext.fetch(descriptor),
                    let item = allItems.first
                {
                    onDrop(item)
                    return true
                }
                return false
            } isTargeted: { targeted in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isTargeted = targeted
                }
            }
    }
}
