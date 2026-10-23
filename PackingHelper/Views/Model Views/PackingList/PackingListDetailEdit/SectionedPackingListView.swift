//
//  SectionedPackingListView.swift
//  PackingHelper
//
//  The single packing view: displays items grouped by their parent section (PackingList)
//  as collapsible sections, with item-level filtering by user/type/day-of.
//
//  Created by Claude on 1/11/26.
//

import SwiftUI
import SwiftData
import OSLog

struct SectionedPackingListView<AssistantPanel: View>: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let users: [User]?
    let lists: [PackingList]
    let title: String?
    let trip: Trip

    // Bindings from container
    @Binding var isAddingNewItem: Bool
    @Binding var newItemList: PackingList?
    @Binding var editingList: PackingList?
    @Binding var showingAddListSheet: Bool
    @Binding var isApplyingDefaultPackingList: Bool
    @Binding var selectedUser: User?
    @Binding var selectedType: ListType?
    @Binding var showDayOfOnly: Bool
    @Binding var isReorderingSections: Bool
    @Binding var scrollToPlaceholder: Bool

    // Inline new item row (state owned by container)
    @Binding var newItemName: String
    @Binding var newItemFieldFocused: Bool
    let newItemCount: Int
    let onSubmitNewItem: () -> Void
    /// Start adding in a list (nil = current target list)
    let onStartAddingItem: (PackingList?) -> Void
    /// Tap on blank space: ends adding if active, otherwise starts adding in that list
    let onTapEmptyArea: (PackingList?) -> Void

    /// Wide layout only: the AI panel slides in from the right, pushing the packed column off screen
    let isShowingAssistantPanel: Bool
    @ViewBuilder let assistantPanel: AssistantPanel

    // Local state
    @State private var pendingPacks = PendingPackTracker()
    @State private var collapsedSections: Set<String> = []
    @State private var expandedSectionsBeforeReorder: Set<String> = []
    @State private var editingItemId: PersistentIdentifier?
    @State private var draggedList: PackingList?

    @State private var isShowingSaveSuccessful: Bool = false
    @State private var listToDelete: PackingList?
    @State private var templateUpdateList: PackingList?
    @State private var itemPendingTemplateSave: Item?
    @State private var templateSaveCount = 0

    var hasMultiplePackers: Bool {
        guard let users = users else { return false }
        return users.count > 1
    }

    var sortedLists: [PackingList] {
        return PackingList.sorted(lists, sortOrder: .byCustomOrder)
    }

    var allPackedItems: [Item] {
        var packedItems: [Item] = []
        for list in lists {
            var listPacked = pendingPacks.settledPacked(list.items ?? [])
            if let user = selectedUser {
                listPacked = listPacked.filter { $0.user?.persistentModelID == user.persistentModelID }
            }
            if let type = selectedType {
                listPacked = listPacked.filter { $0.type == type }
            }
            if showDayOfOnly {
                listPacked = listPacked.filter { $0.isDayOf }
            }
            packedItems.append(contentsOf: listPacked)
        }
        return Item.sorted(packedItems, sortOrder: .byCustomOrder)
    }

    /// Items across all sections that aren't in their section's template yet.
    /// Empty once the trip's template review is done: whatever wasn't added was declined.
    var templateCandidateIDs: Set<PersistentIdentifier> {
        guard !trip.templateReviewDismissed else { return [] }
        return Set(lists.flatMap { list in
            list.templateCandidates.flatMap { $0.items.map(\.persistentModelID) }
        })
    }

    func isExpanded(for list: PackingList) -> Binding<Bool> {
        Binding(
            get: { !collapsedSections.contains(list.collapseKey) },
            set: { expanded in
                let id = list.collapseKey
                if expanded {
                    collapsedSections.remove(id)
                } else {
                    collapsedSections.insert(id)
                }
                SectionCollapseStateManager.saveCollapsedSections(collapsedSections, for: trip.uuid)
            }
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
        Group {
            if horizontalSizeClass == .regular {
                WidePackingColumns(isShowingTrailing: isShowingAssistantPanel) {
                    packedColumn
                } available: {
                    VStack(spacing: 16) {
                        sectionsList
                        emptyStateAndTapZone
                    }
                } trailing: {
                    assistantPanel
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        sectionsList

                        // Global packed items section
                        if !allPackedItems.isEmpty {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 2)
                                .padding(.horizontal)
                            PackedItemsSection(
                                items: allPackedItems,
                                onTogglePacked: togglePacked,
                                onDeleteItem: deleteItem,
                                templateCandidateIDs: templateCandidateIDs,
                                onAddToTemplate: addItemToTemplate
                            )
                        }

                        emptyStateAndTapZone
                    }
                    .padding(.vertical)
                    .padding(.horizontal, 8)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .onAppear {
            loadCollapseState()
        }
        .onChange(of: newItemList) { _, targetList in
            // Auto-expand the target section when it changes
            if let targetList {
                let id = targetList.collapseKey
                if collapsedSections.contains(id) {
                    withAnimation { collapsedSections.remove(id) }
                }
                // Scroll to placeholder — delay to allow section expansion to render
                if isAddingNewItem {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation {
                            proxy.scrollTo(
                                NewItemRow.scrollID(for: targetList),
                                anchor: .bottom
                            )
                        }
                    }
                }
            }
        }
        .onChange(of: isAddingNewItem) { _, isAdding in
            if isAdding, let targetList = newItemList {
                // The inline row only renders in an expanded section
                let id = targetList.collapseKey
                if collapsedSections.contains(id) {
                    withAnimation { collapsedSections.remove(id) }
                }
                withAnimation {
                    proxy.scrollTo(
                        NewItemRow.scrollID(for: targetList),
                        anchor: .bottom
                    )
                }
            }
        }
        .onChange(of: isReorderingSections) { _, isReordering in
            if isReordering {
                enterReorderMode()
            } else {
                exitReorderMode()
            }
        }
        .onChange(of: scrollToPlaceholder) { _, shouldScroll in
            if shouldScroll, let targetList = newItemList {
                scrollToPlaceholder = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        proxy.scrollTo(
                            NewItemRow.scrollID(for: targetList),
                            anchor: .bottom
                        )
                    }
                }
            }
        }
        .sheet(item: $templateUpdateList) { list in
            TemplateUpdateSheet(sections: [list])
        }
        .alert(
            "Add to Template?",
            isPresented: Binding(get: { itemPendingTemplateSave != nil }, set: { if !$0 { itemPendingTemplateSave = nil } }),
            presenting: itemPendingTemplateSave
        ) { item in
            Button("Add to Template") {
                confirmAddToTemplate(item)
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text(addToTemplateMessage(for: item))
        }
        .sensoryFeedback(.success, trigger: templateSaveCount)
        .alert("List saved as default", isPresented: $isShowingSaveSuccessful) {
            Button("OK", role: .cancel) {}
        }
        .alert(
            "Delete List",
            isPresented: Binding(get: { listToDelete != nil }, set: { if !$0 { listToDelete = nil } }),
            presenting: listToDelete
        ) { list in
            Button("Delete", role: .destructive) {
                deleteList(list)
                listToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                listToDelete = nil
            }
        } message: { list in
            if list.appliedFromTemplate != nil {
                Text("This will delete \"\(list.name)\" from your trip. The template list it was applied from will not be deleted.")
            } else {
                Text("Are you sure you want to delete \"\(list.name)\"?")
            }
        }
        } // end ScrollViewReader
    }

    // MARK: - Content

    @ViewBuilder
    private var sectionsList: some View {
        // List sections with drag-and-drop reordering
        ForEach(Array(sortedLists.enumerated()), id: \.element.id) { index, list in
            VStack(spacing: 0) {
                // Drop zone before first section
                if isReorderingSections && index == 0 {
                    SectionDropZone(
                        insertionIndex: 0,
                        isDragging: true,
                        onDrop: { droppedList in
                            handleSectionReorder(list: droppedList, to: 0)
                        }
                    )
                }

                PackingListSection(
                    packingList: list,
                    users: users,
                    isExpanded: isExpanded(for: list),
                    editingItemId: $editingItemId,
                    selectedUser: selectedUser,
                    selectedType: selectedType,
                    showDayOfOnly: showDayOfOnly,
                    onTogglePacked: togglePacked,
                    onUpdateItem: updateItem,
                    onDeleteItem: deleteItem,
                    onEditList: { editingList = list },
                    onDeleteList: { listToDelete = list },
                    onSaveAsDefault: { saveListAsDefault(list) },
                    onItemReorder: handleItemReorder,
                    onCrossListDrop: handleCrossListMove,
                    onAddItemToList: { targetList in
                        onStartAddingItem(targetList)
                    },
                    templateCandidateIDs: templateCandidateIDs,
                    onAddToTemplate: addItemToTemplate,
                    onUpdateTemplate: { templateUpdateList = list },
                    isReorderMode: isReorderingSections,
                    pendingPacks: pendingPacks,
                    isAddingNewItem: isAddingNewItem,
                    targetList: newItemList,
                    newItemName: $newItemName,
                    newItemFieldFocused: $newItemFieldFocused,
                    newItemCount: newItemCount,
                    onSubmitNewItem: onSubmitNewItem,
                    onTapEmptyArea: { list in onTapEmptyArea(list) }
                )
                .draggable(PackingListTransferData(list: list)) {
                    // Section drag preview
                    PackingListSectionHeader(
                        packingList: list,
                        isExpanded: .constant(false),
                        onAddItem: {},
                        onEditList: {},
                        onDeleteList: {},
                        onSaveAsDefault: {}
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThickMaterial)
                    .clipShape(.rect(cornerRadius: 12))
                }
                .onAppear {
                    // Track when dragging starts
                    if draggedList?.persistentModelID == list.persistentModelID {
                        draggedList = list
                    }
                }

                // Drop zone after each section (reorder mode only)
                if isReorderingSections {
                    SectionDropZone(
                        insertionIndex: index + 1,
                        isDragging: true,
                        onDrop: { droppedList in
                            handleSectionReorder(list: droppedList, to: index + 1)
                        }
                    )
                }
            }

            // Divider between sections (not in reorder mode, not after last)
            if !isReorderingSections && index < sortedLists.count - 1 {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 2)
                    .padding(.horizontal, 8)
            }
        }
    }

    /// Wide layout: the left column holds every packed item
    @ViewBuilder
    private var packedColumn: some View {
        if allPackedItems.isEmpty {
            NothingPackedView()
        } else {
            PackedItemsSection(
                items: allPackedItems,
                onTogglePacked: togglePacked,
                onDeleteItem: deleteItem,
                templateCandidateIDs: templateCandidateIDs,
                onAddToTemplate: addItemToTemplate,
                isCollapsible: false
            )
        }
    }

    @ViewBuilder
    private var emptyStateAndTapZone: some View {
        // Empty state
        if lists.allSatisfy({ ($0.items?.isEmpty ?? true) }) && !isAddingNewItem {
            EmptyStateView()
                .padding(.top, 60)
        }

        // Blank space below everything: tap to add to the current list, or to finish adding
        if !isReorderingSections {
            AddItemTapZone(minHeight: 120) {
                onTapEmptyArea(nil)
            }
        }
    }

    private func loadCollapseState() {
        collapsedSections = SectionCollapseStateManager.loadCollapsedSections(for: trip.uuid)

        // Auto-collapse empty lists
        for list in lists where (list.items?.isEmpty ?? true) {
            let id = list.collapseKey
            if !collapsedSections.contains(id) {
                collapsedSections.insert(id)
            }
        }
    }

    private func togglePacked(_ item: Item) {
        pendingPacks.toggle(item)
    }

    private func updateItem(_ item: Item, name: String, count: Int) {
        withAnimation {
            item.name = name
            item.count = count
            // Only clear if another row hasn't already taken over editing
            if editingItemId == item.persistentModelID {
                editingItemId = nil
            }
        }
    }

    private func deleteItem(_ item: Item) {
        withAnimation(.packingSpring) {
            modelContext.delete(item)
        }
    }

    /// Swipe action: saving changes the template for every future trip, so confirm first
    private func addItemToTemplate(_ item: Item) {
        itemPendingTemplateSave = item
    }

    private func confirmAddToTemplate(_ item: Item) {
        guard let list = item.list,
              let candidate = list.templateCandidates.first(where: { $0.key == item.name.itemMatchKey })
        else { return }
        withAnimation(.packingSpring) {
            list.saveToTemplate([candidate], in: modelContext)
        }
        templateSaveCount += 1
    }

    private func addToTemplateMessage(for item: Item) -> String {
        let source = item.list?.appliedFromTemplate
        let templateName = source?.name ?? "this"
        var templateLabel = "your \"\(templateName)\" template"
        if hasMultiplePackers, let owner = source?.user {
            templateLabel = "\(owner.name)'s \"\(templateName)\" template"
        }

        var message = "\"\(item.name)\" will be saved to \(templateLabel), so future trips that use it will include this item."
        if item.count > 1 {
            message += " It will start with a count of 1."
        }
        message += " Trips that already use this template won't change."
        return message
    }

    private func deleteList(_ list: PackingList) {
        guard !list.isDefault else { return }
        withAnimation(.packingSpring) {
            modelContext.delete(list)
        }
    }

    private func saveListAsDefault(_ list: PackingList) {
        withAnimation {
            let newDefaultList = PackingList.copyAsTemplate(list)
            modelContext.insert(newDefaultList)
            isShowingSaveSuccessful = true
        }
    }

    private func handleItemReorder(item: Item, in list: PackingList, to newIndex: Int) {
        withAnimation(.packingSpring) {
            AppLogger.views.debug("Reordering item \(item.name) to index \(newIndex)")
            SortOrderManager.reorderItems(in: list, moving: item, to: newIndex)
        }
    }

    private func handleCrossListMove(item: Item, to targetList: PackingList, at index: Int) {
        withAnimation(.packingSpring) {
            AppLogger.views.debug("Moving item \(item.name) to list \(targetList.name) at index \(index)")
            SortOrderManager.moveItem(item, to: targetList, at: index)
        }
    }

    private func handleSectionReorder(list: PackingList, to newIndex: Int) {
        withAnimation(.packingSpring) {
            AppLogger.views.debug("Reordering section \(list.name) to index \(newIndex)")
            var mutableLists = sortedLists
            SortOrderManager.reorderLists(&mutableLists, moving: list, to: newIndex)
        }
    }

    private func enterReorderMode() {
        // Save which sections are currently expanded
        expandedSectionsBeforeReorder = Set(sortedLists.compactMap { list in
            let id = list.collapseKey
            return collapsedSections.contains(id) ? nil : id
        })
        // Collapse all sections
        withAnimation {
            for list in sortedLists {
                collapsedSections.insert(list.collapseKey)
            }
        }
    }

    private func exitReorderMode() {
        // Restore previously expanded sections
        withAnimation {
            collapsedSections = collapsedSections.subtracting(expandedSectionsBeforeReorder)
            expandedSectionsBeforeReorder = []
        }
        SectionCollapseStateManager.saveCollapsedSections(collapsedSections, for: trip.uuid)
    }
}
