//
//  PackingEditor.swift
//  PackingHelper
//
//  The packing screen's editing state and actions: the inline add-item flow, Remove Items
//  mode and its undo stack, template item editing, and the check-off tracker. Owned by
//  PackingListContainerView and shared with the Focus pages through the environment.
//

import SwiftData
import SwiftUI

@MainActor
@Observable
final class PackingEditor {

    // MARK: - Add Item

    /// The inline new item row is showing
    var isAdding = false
    var name = ""
    var count = 1
    /// Packer for new items (trip packing only)
    var user: User?
    /// Section the new item row is in
    var targetList: PackingList?
    /// Plain `Bool` (not `@FocusState`) because `PersistentTextField` is UIKit-backed
    var isFieldFocused = false
    /// Template editor: scroll the new item row into view after Return
    var scrollToPlaceholder = false

    // MARK: - Remove Items (trip packing)

    /// Tap a card's minus to delete it right away
    var isRemovingItems = false
    /// Items deleted in Remove Items mode, newest last; Undo puts back the last one
    var removedItems: [RemovedItem] = []

    // MARK: - Template Editing

    var editingItemId: PersistentIdentifier?

    // MARK: - Check-Off

    /// Checked items stay in place briefly before moving to Packed
    let pendingPacks = PendingPackTracker()

    // MARK: - Setup

    let context: PackingListContext
    /// Set by the container when it appears (the environment value isn't available earlier)
    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var finishAddingTask: Task<Void, Never>?

    init(context: PackingListContext) {
        self.context = context
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Lists

    var lists: [PackingList] {
        if let trip = context.trip {
            return trip.lists ?? []
        } else if let singleList = context.singleList {
            return [singleList]
        }
        return []
    }

    /// Lists in the same order as the sections in `FocusPackingView`
    var sortedLists: [PackingList] {
        PackingList.sorted(lists, sortOrder: .byCustomOrder)
    }

    /// `targetList` if it still belongs to this trip and hasn't been deleted
    var resolvedTargetList: PackingList? {
        guard let targetList, !targetList.isDeleted,
              lists.contains(where: { $0.persistentModelID == targetList.persistentModelID }) else {
            return nil
        }
        return targetList
    }

    private var fallbackTargetList: PackingList? {
        lists.first(where: { $0.isDefault }) ?? sortedLists.first
    }

    /// Falls back when there is no target or it was deleted, so we never insert into a deleted list
    func resetTargetListIfNeeded() {
        if resolvedTargetList == nil {
            targetList = fallbackTargetList
        }
    }

    func isTarget(_ list: PackingList) -> Bool {
        isAdding && targetList?.persistentModelID == list.persistentModelID
    }

    // MARK: - Add Item Actions

    /// Shows the inline new item row in `list` (or the current target list) and focuses it
    func startAdding(in list: PackingList?) {
        // Items need a section; with none, the Add a Section page is the way forward
        guard !(context.isTrip && lists.isEmpty) else { return }
        if let list, list.persistentModelID != targetList?.persistentModelID {
            // Save anything typed for the previous list before the row moves
            insertItem()
            targetList = list
        }
        isFieldFocused = true
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            isAdding = true
        }
    }

    /// Reminders-style: tapping blank space finishes the current entry, or starts a new one
    func handleTapOnEmptyArea(in list: PackingList?) {
        if isAdding {
            finishAdding()
        } else {
            startAdding(in: list)
        }
    }

    /// Return key: save and keep the row open for the next item; Return on an empty row closes it
    func addAndContinue() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            finishAdding()
            return
        }
        insertItem()
        scrollToPlaceholder = true
    }

    /// Saves any typed text, then dismisses the keyboard before animating the row away
    func finishAdding() {
        insertItem()
        isFieldFocused = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            name = ""
            count = 1
            isAdding = false
        }
    }

    /// Call when the field's focus changes. Focus drops briefly when the inline row moves to
    /// another section, so only finish if it is still unfocused after the row has re-rendered.
    func focusChanged(to isFocused: Bool) {
        guard !isFocused && isAdding else { return }
        finishAddingTask?.cancel()
        finishAddingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            if !self.isFieldFocused && self.isAdding {
                self.finishAdding()
            }
        }
    }

    private func insertItem() {
        guard let list = context.isTrip ? (resolvedTargetList ?? fallbackTargetList) : context.singleList,
              let modelContext else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        withAnimation(.packingSpring) {
            let newItem = Item(
                name: trimmedName,
                category: "",
                count: count,
                isPacked: false,
                sortOrder: SortOrderManager.nextSortOrder(for: list)
            )
            newItem.user = context.isTrip ? user : nil
            modelContext.insert(newItem)
            list.addItem(newItem)

            name = ""
            count = 1
        }
    }

    // MARK: - Remove Items Actions

    func startRemoving() {
        if isAdding {
            finishAdding()
        }
        withAnimation(.packingSpring) { isRemovingItems = true }
    }

    func stopRemoving() {
        withAnimation(.packingSpring) { isRemovingItems = false }
    }

    func remove(_ item: Item) {
        if let removed = RemovedItem(item) {
            removedItems.append(removed)
        }
        withAnimation(.packingSpring) { modelContext?.delete(item) }
    }

    /// Puts back the most recently removed item whose section still exists
    func undoRemove() {
        guard let modelContext else { return }
        while let removed = removedItems.popLast() {
            guard !removed.list.isDeleted,
                  lists.contains(where: { $0.persistentModelID == removed.list.persistentModelID })
            else { continue }
            withAnimation(.packingSpring) { removed.restore(in: modelContext) }
            return
        }
    }

    // MARK: - Template Editing Actions

    func updateItem(_ item: Item, name: String, count: Int) {
        withAnimation {
            item.name = name
            item.count = count
            // Only clear if another row hasn't already taken over editing
            if editingItemId == item.persistentModelID {
                editingItemId = nil
            }
        }
    }

    func deleteItem(_ item: Item) {
        withAnimation(.packingSpring) { modelContext?.delete(item) }
    }

    func reorderItem(_ item: Item, in list: PackingList, to newIndex: Int) {
        withAnimation(.packingSpring) {
            SortOrderManager.reorderItems(in: list, moving: item, to: newIndex)
        }
    }
}
