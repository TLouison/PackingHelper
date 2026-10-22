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
    var isTemplating: Bool = false
    var targetList: PackingList? = nil  // For sectioned view cross-list drops

    @Binding var editingItemId: PersistentIdentifier?
    let onTogglePacked: (Item) -> Void
    let onUpdateItem: (Item, String, Int) -> Void
    let onDeleteItem: (Item) -> Void
    let onReorder: (Item, Int) -> Void
    var onCrossListMove: ((Item, PackingList, Int) -> Void)? = nil
    /// Items that aren't in their section's template yet
    var templateCandidateIDs: Set<PersistentIdentifier> = []
    var onAddToTemplate: ((Item) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            // Drop zone at top
            ItemDropZone(insertionIndex: 0) { droppedItem in
                handleDrop(at: 0, item: droppedItem)
            }

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if editingItemId == item.persistentModelID {
                    EditableItemRow(
                        item: item,
                        isTemplating: isTemplating,
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
                        isTemplating: isTemplating,
                        onTogglePacked: { onTogglePacked(item) },
                        onEdit: { editingItemId = item.persistentModelID },
                        onDelete: { onDeleteItem(item) },
                        onAddToTemplate: addToTemplateAction(for: item)
                    )
                    .draggable(ItemTransferData(item: item)) {
                        // Drag preview
                        UnifiedItemRow(
                            item: item,
                            isTemplating: isTemplating,
                            onTogglePacked: {},
                            onEdit: {},
                            onDelete: {}
                        ).rowContent
                    }
                }

                // Drop zone after each item
                ItemDropZone(insertionIndex: index + 1) { droppedItem in
                    handleDrop(at: index + 1, item: droppedItem)
                }
            }
        }
    }

    private func addToTemplateAction(for item: Item) -> (() -> Void)? {
        guard let onAddToTemplate, templateCandidateIDs.contains(item.persistentModelID) else { return nil }
        return { onAddToTemplate(item) }
    }

    private func handleDrop(at index: Int, item: Item) {
        // Check if this is a cross-list move
        if let targetList = targetList,
            let onCrossListMove = onCrossListMove,
            item.list?.persistentModelID != targetList.persistentModelID
        {
            // Cross-list move
            onCrossListMove(item, targetList, index)
        } else {
            // Same-list reorder
            onReorder(item, index)
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

// MARK: - Section Drop Zone Component

struct SectionDropZone: View {
    let insertionIndex: Int
    let isDragging: Bool
    let onDrop: (PackingList) -> Void

    @State private var isTargeted = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Rectangle()
            .fill(isTargeted ? Color.blue.opacity(0.3) : Color.clear)
            .frame(height: isTargeted ? 60 : 16)
            .clipShape(.rect(cornerRadius: 8))
            .padding(.vertical, isTargeted ? 4 : 0)
            .contentShape(Rectangle())
            .dropDestination(for: PackingListTransferData.self) { lists, location in
                guard let transferData = lists.first else { return false }

                // Look up the list from the model context using UUID
                let descriptor = FetchDescriptor<PackingList>(
                    predicate: #Predicate<PackingList> { list in
                        list.uuid == transferData.listUUID
                    }
                )
                if let allLists = try? modelContext.fetch(descriptor),
                    let list = allLists.first
                {
                    onDrop(list)
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
