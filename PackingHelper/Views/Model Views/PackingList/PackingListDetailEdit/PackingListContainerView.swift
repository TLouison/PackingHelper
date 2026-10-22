//
//  PackingListContainerView.swift
//  PackingHelper
//
//  Container that renders the packing screen.
//  Trip context: SectionedPackingListView with filter state.
//  Single-list context: inline single-section view (templates/detail).
//
//  Created by Claude on 1/11/26.
//

import SwiftData
import SwiftUI

// MARK: - Container View

struct PackingListContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseManager.self) private var purchaseManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let context: PackingListContext
    let users: [User]?
    let title: String?

    @State private var editingList: PackingList? = nil
    @State private var showingAddListSheet: Bool = false
    @State private var isApplyingDefaultPackingList: Bool = false
    @State private var isAddingNewItem: Bool = false
    @State private var selectedUser: User?
    @State private var selectedType: ListType? = nil
    @State private var showDayOfOnly: Bool = false
    @State private var isReorderingSections: Bool = false

    // AI assistant (trip context only)
    @State private var showingAIAssistant: Bool = false
    @State private var showingAIPaywall: Bool = false
    /// Show the paywall once the assistant sheet finishes dismissing (two
    /// sheets can't present back-to-back in the same update).
    @State private var showPaywallAfterAIDismiss: Bool = false

    // Centralized add-item state
    @State private var newItemName = ""
    @State private var newItemCount = 1
    @State private var newItemUser: User? = nil
    @State private var newItemList: PackingList? = nil
    @State private var newItemFieldFocused = false
    @State private var scrollToPlaceholder = false

    // Single list mode state
    @State private var isShowingListSettings: Bool = false
    @State private var isShowingTemplateInfo: Bool = false
    @State private var isShowingSaveSuccessful: Bool = false
    @State private var isDeleted: Bool = false

    // Single list mode item editing (trip context manages this inside SectionedPackingListView)
    @State private var singleListEditingItemId: PersistentIdentifier? = nil
    @State private var singleListPendingPacks = PendingPackTracker()

    // MARK: - Initializers

    /// Initialize with a single packing list (template or trip list)
    init(packingList: PackingList) {
        self.context = .singleList(packingList)
        self.users = nil
        self.title = packingList.name
    }

    /// Initialize with a trip
    init(trip: Trip, users: [User]?, title: String?) {
        self.context = .trip(trip)
        self.users = users
        self.title = title
    }

    // MARK: - Computed Properties

    private var lists: [PackingList] {
        if let trip = context.trip {
            return trip.lists ?? []
        } else if let singleList = context.singleList {
            return [singleList]
        }
        return []
    }

    private var hasMultiplePackers: Bool {
        guard let users = users else { return false }
        return users.count > 1
    }

    private var isTemplating: Bool {
        context.singleList?.template == true
    }

    /// Whether to show the user selector
    private var showUserSelector: Bool {
        context.isTrip && hasMultiplePackers
    }

    /// Whether to show the summary bar
    private var showSummaryBar: Bool {
        if context.isTrip {
            return true
        } else if let singleList = context.singleList {
            return !singleList.template
        }
        return false
    }

    private var baseView: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            packingListView
        }
        .safeAreaInset(edge: .bottom) {
            if isAddingNewItem && !isReorderingSections {
                newItemAccessoryBar
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isReorderingSections {
                doneButton
            } else if !isAddingNewItem {
                fabButton
            }
        }
        .navigationTitle(title ?? "Packing")
        .navigationBarTitleDisplayMode(isTemplating ? .large : .inline)
        .sheet(item: $editingList) { list in
            if let trip = context.trip {
                PackingListEditView(
                    packingList: list,
                    trip: trip,
                    isDeleted: .constant(false)
                )
                .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $showingAddListSheet) {
            if let trip = context.trip {
                PackingListEditView(
                    packingList: nil,
                    trip: trip,
                    onListCreated: { newList in
                        newItemList = newList
                    }, isDeleted: .constant(false)
                )
                .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $isApplyingDefaultPackingList) {
            if let trip = context.trip {
                PackingListApplyDefaultView(trip: trip)
            }
        }
        .sheet(isPresented: $isShowingListSettings) {
            if let singleList = context.singleList {
                PackingListEditView(
                    packingList: singleList,
                    isTemplate: singleList.template,
                    isDeleted: $isDeleted
                )
            }
        }
        .sheet(isPresented: $isShowingTemplateInfo) {
            if let singleList = context.singleList {
                TemplateListInfoView(list: singleList)
                    .presentationDetents([.fraction(0.65), .large])
            }
        }
        .sheet(isPresented: $showingAIAssistant, onDismiss: {
            if showPaywallAfterAIDismiss {
                showPaywallAfterAIDismiss = false
                showingAIPaywall = true
            }
        }) {
            if let trip = context.trip {
                AIAssistantSheet(
                    trip: trip,
                    users: users,
                    targetUser: $newItemUser,
                    onSubscriptionLapsed: {
                        showPaywallAfterAIDismiss = true
                        showingAIAssistant = false
                    }
                )
                .presentationDetents([.large])
            }
        }
        .sheet(isPresented: $showingAIPaywall) {
            PlusPaywallView()
        }
    }

    var body: some View {
        baseView
        .alert("List saved as default", isPresented: $isShowingSaveSuccessful) {
            Button("OK", role: .cancel) {}
        }
        .onChange(of: isDeleted) {
            dismiss()
        }
        .onChange(of: newItemFieldFocused) { _, isFocused in
            guard !isFocused && isAddingNewItem else { return }
            // Focus drops briefly when the inline row moves to another section,
            // so only finish if it is still unfocused after the row has re-rendered
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if !newItemFieldFocused && isAddingNewItem {
                    finishAddingNewItem()
                }
            }
        }
        .toolbar {
            containerToolbar
        }
        .onAppear {
            // Only seed on first appearance so returning to this view keeps the user's picks
            if newItemUser == nil {
                newItemUser = selectedUser ?? users?.first
            }
            if resolvedNewItemList == nil {
                newItemList = fallbackNewItemList
            }
        }
        .onChange(of: selectedUser) { _, user in
            // Keep new items assigned to the packer being filtered on, otherwise they vanish on add
            if let user {
                newItemUser = user
            }
        }
        .onChange(of: lists.map(\.persistentModelID)) {
            // The target section was deleted; fall back so we never insert into a deleted list
            if resolvedNewItemList == nil {
                newItemList = fallbackNewItemList
            }
        }
    }

    /// `newItemList` if it still belongs to this trip and hasn't been deleted
    private var resolvedNewItemList: PackingList? {
        guard let newItemList, !newItemList.isDeleted,
              lists.contains(where: { $0.persistentModelID == newItemList.persistentModelID }) else {
            return nil
        }
        return newItemList
    }

    private var fallbackNewItemList: PackingList? {
        lists.first(where: { $0.isDefault }) ?? lists.first
    }

    // MARK: - New Item Accessory Bar

    /// Sits directly above the keyboard while the inline new item row is focused
    private var newItemAccessoryBar: some View {
        HStack(spacing: 8) {
            if context.isTrip {
                listPickerMenu
            }

            if hasMultiplePackers {
                UserPickerView(
                    selectedUser: $newItemUser,
                    style: .menu,
                    allowAll: false
                )
            }

            Spacer()

            ItemCountStepper(count: $newItemCount)
                .padding(.horizontal, 4)
                .opaqueGlassCapsule()
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var listPickerMenu: some View {
        Menu {
            ForEach(lists, id: \.id) { list in
                Button {
                    newItemList = list
                } label: {
                    if list.id == newItemList?.id {
                        Label(list.name, systemImage: "checkmark")
                    } else {
                        Text(list.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet")
                    .font(.caption)
                Text(resolvedNewItemList?.name ?? "Select List")
                    .fontWeight(.medium)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .opaqueGlassCapsule()
        }
        .disabled(lists.count <= 1)
    }

    // MARK: - FAB Button

    private var fabButton: some View {
        Button { startAddingNewItem(in: nil) } label: {
            Image(systemName: "plus.circle.fill")
                .resizable()
                .foregroundStyle(.blue)
        }
        .accessibilityLabel("Add Item")
        .frame(width: 60, height: 60)
        .glassEffectIfAvailable()
        .padding(.trailing, 16)
        .padding(.bottom, 16)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.3, anchor: .bottomTrailing).combined(with: .opacity),
            removal: .scale(scale: 0.3, anchor: .bottomTrailing).combined(with: .opacity)
        ))
    }

    // MARK: - Done Button (Reorder Mode)

    private var doneButton: some View {
        Button("Done") {
            isReorderingSections = false
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.trailing, 16)
        .padding(.bottom, 16)
    }

    private var packingListView: some View {
        VStack(spacing: 0) {
            // User selector (trip context with multiple packers only)
            if showUserSelector {
                UserSelector(
                    users: users ?? [],
                    selectedUser: $selectedUser
                )
            }

            if context.isTrip, let trip = context.trip {
                SectionedPackingListView(
                    users: users,
                    lists: lists,
                    title: title,
                    trip: trip,
                    isAddingNewItem: $isAddingNewItem,
                    newItemList: $newItemList,
                    editingList: $editingList,
                    showingAddListSheet: $showingAddListSheet,
                    isApplyingDefaultPackingList: $isApplyingDefaultPackingList,
                    selectedUser: $selectedUser,
                    selectedType: $selectedType,
                    showDayOfOnly: $showDayOfOnly,
                    isReorderingSections: $isReorderingSections,
                    scrollToPlaceholder: $scrollToPlaceholder,
                    newItemName: $newItemName,
                    newItemFieldFocused: $newItemFieldFocused,
                    newItemCount: newItemCount,
                    onSubmitNewItem: addNewItemAndContinue,
                    onStartAddingItem: startAddingNewItem(in:),
                    onTapEmptyArea: handleTapOnEmptyArea(in:)
                )
            } else if let singleList = context.singleList {
                singleListView(list: singleList)
            }

            // Summary bar hidden when adding to prevent stacking with input bar
            if showSummaryBar && !isAddingNewItem {
                PackingSummaryBar(packingLists: lists)
            }
        }
    }

    @ViewBuilder
    private func singleListView(list: PackingList) -> some View {
        let allItems = Item.sorted(list.items ?? [], sortOrder: .byCustomOrder)
        let unpackedItems = Item.sorted(
            singleListPendingPacks.visibleUnpacked(list.items ?? []),
            sortOrder: .byCustomOrder
        )
        let rowItems = isTemplating ? allItems : unpackedItems

        let packedItems = Item.sorted(
            singleListPendingPacks.settledPacked(list.items ?? []),
            sortOrder: .byCustomOrder
        )

        ScrollViewReader { proxy in
            Group {
                if horizontalSizeClass == .regular && !isTemplating {
                    // Regular width (iPhone Duo unfolded, iPad): packed on the left, available on the right
                    WidePackingColumns {
                        if packedItems.isEmpty {
                            NothingPackedView()
                        } else {
                            PackedItemsSection(
                                items: packedItems,
                                onTogglePacked: { item in singleListPendingPacks.toggle(item) },
                                onDeleteItem: { item in withAnimation(.packingSpring) { modelContext.delete(item) } },
                                isCollapsible: false
                            )
                        }
                    } available: {
                        VStack(spacing: 0) {
                            singleListAvailableContent(list: list, allItems: allItems, unpackedItems: unpackedItems, rowItems: rowItems)
                            singleListTapZone
                        }
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            singleListAvailableContent(list: list, allItems: allItems, unpackedItems: unpackedItems, rowItems: rowItems)

                            if !isTemplating && !packedItems.isEmpty {
                                PackedItemsSection(
                                    items: packedItems,
                                    onTogglePacked: { item in singleListPendingPacks.toggle(item) },
                                    onDeleteItem: { item in withAnimation(.packingSpring) { modelContext.delete(item) } }
                                )
                            }

                            singleListTapZone
                        }
                        .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .onChange(of: isAddingNewItem) { _, isAdding in
                if isAdding {
                    withAnimation { proxy.scrollTo(NewItemRow.scrollID(for: list), anchor: .bottom) }
                }
            }
            .onChange(of: scrollToPlaceholder) { _, shouldScroll in
                guard shouldScroll else { return }
                scrollToPlaceholder = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        proxy.scrollTo(NewItemRow.scrollID(for: list), anchor: .bottom)
                    }
                }
            }
        }
    }

    /// Item rows, inline new item row, and empty state for a single list
    @ViewBuilder
    private func singleListAvailableContent(list: PackingList, allItems: [Item], unpackedItems: [Item], rowItems: [Item]) -> some View {
        if isTemplating {
            ReorderableItemsSection(
                items: allItems,
                isTemplating: true,
                editingItemId: $singleListEditingItemId,
                onTogglePacked: { _ in },
                onUpdateItem: updateSingleListItem,
                onDeleteItem: { item in
                    withAnimation(.packingSpring) { modelContext.delete(item) }
                },
                onReorder: { item, newIndex in
                    withAnimation(.packingSpring) {
                        SortOrderManager.reorderItems(in: list, moving: item, to: newIndex)
                    }
                }
            )
        } else {
            ReorderableItemsSection(
                items: unpackedItems,
                isTemplating: false,
                editingItemId: $singleListEditingItemId,
                onTogglePacked: { item in
                    singleListPendingPacks.toggle(item)
                },
                onUpdateItem: updateSingleListItem,
                onDeleteItem: { item in
                    withAnimation(.packingSpring) { modelContext.delete(item) }
                },
                onReorder: { item, newIndex in
                    withAnimation(.packingSpring) {
                        SortOrderManager.reorderItems(in: list, moving: item, to: newIndex)
                    }
                }
            )
        }

        if isAddingNewItem {
            NewItemRow(
                itemName: $newItemName,
                isFocused: $newItemFieldFocused,
                itemCount: newItemCount,
                showsCheckbox: !isTemplating,
                onSubmitReturn: addNewItemAndContinue,
                onDeleteEmpty: {
                    // Backspace on the empty new row moves editing up to the last item
                    if let lastItem = rowItems.last {
                        singleListEditingItemId = lastItem.persistentModelID
                    }
                }
            )
            .id(NewItemRow.scrollID(for: list))
        }

        if allItems.isEmpty && !isAddingNewItem {
            EmptyStateView()
                .padding(.top, 60)
        }
    }

    /// Blank space below the list: tap to add, or to finish adding
    private var singleListTapZone: some View {
        AddItemTapZone(minHeight: 120) {
            handleTapOnEmptyArea(in: nil)
        }
    }

    @ToolbarContentBuilder
    private var containerToolbar: some ToolbarContent {
        if isAddingNewItem {
            addingItemToolbar
        } else if context.isTrip {
            tripToolbar
        } else {
            singleListToolbar
        }
    }

    @ToolbarContentBuilder
    private var addingItemToolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button { finishAddingNewItem() } label: {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
            }
            .accessibilityLabel("Done")
        }
    }

    @ToolbarContentBuilder
    private var tripToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                if purchaseManager.hasUnlockedPlus {
                    showingAIAssistant = true
                } else {
                    showingAIPaywall = true
                }
            } label: {
                Image(systemName: "sparkles")
                    .overlay(alignment: .topTrailing) {
                        if !purchaseManager.hasUnlockedPlus {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.white, .blue)
                                .offset(x: 6, y: -6)
                        }
                    }
            }
            .accessibilityLabel("AI Packing Assistant")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    showingAddListSheet.toggle()
                } label: {
                    Label("Create Section", systemImage: "plus")
                }

                Button {
                    isApplyingDefaultPackingList.toggle()
                } label: {
                    Label("Apply Template", systemImage: "doc.on.doc")
                }

                Divider()

                Button {
                    isReorderingSections = true
                } label: {
                    Label("Reorder Sections", systemImage: "arrow.up.arrow.down")
                }
            } label: {
                Label("Options", systemImage: "ellipsis.circle")
            }
        }
    }

    @ToolbarContentBuilder
    private var singleListToolbar: some ToolbarContent {
        if let singleList = context.singleList {
            if !singleList.template && !singleList.isDefault {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Save As Default") {
                            saveListAsDefault(singleList)
                        }
                    } label: {
                        Label("Save As Default", systemImage: "square.and.arrow.up")
                    }
                }
            }
            if singleList.template {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingTemplateInfo.toggle()
                    } label: {
                        Label("List Info", systemImage: "info.circle")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingListSettings.toggle()
                } label: {
                    Label("List Settings", systemImage: "gear")
                }
            }
        }
    }

    // MARK: - Add Item Actions

    /// Shows the inline new item row in `list` (or the current target list) and focuses it
    private func startAddingNewItem(in list: PackingList?) {
        if let list, list.persistentModelID != newItemList?.persistentModelID {
            // Save anything typed for the previous list before the row moves
            insertNewItem()
            newItemList = list
        }
        newItemFieldFocused = true
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            isAddingNewItem = true
        }
    }

    /// Reminders-style: tapping blank space finishes the current entry, or starts a new one
    private func handleTapOnEmptyArea(in list: PackingList?) {
        if isAddingNewItem {
            finishAddingNewItem()
        } else {
            startAddingNewItem(in: list)
        }
    }

    /// Return key: save and keep the row open for the next item; Return on an empty row closes it
    private func addNewItemAndContinue() {
        guard !newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            finishAddingNewItem()
            return
        }
        insertNewItem()
        scrollToPlaceholder = true
    }

    /// Saves any typed text, then dismisses the keyboard before animating the row away
    private func finishAddingNewItem() {
        insertNewItem()
        newItemFieldFocused = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            newItemName = ""
            newItemCount = 1
            isAddingNewItem = false
        }
    }

    private func insertNewItem() {
        guard let list = context.isTrip ? (resolvedNewItemList ?? fallbackNewItemList) : context.singleList else { return }
        let name = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        withAnimation(.packingSpring) {
            let newItem = Item(
                name: name,
                category: "",
                count: newItemCount,
                isPacked: false,
                sortOrder: SortOrderManager.nextSortOrder(for: list),
                type: .packing,
                isDayOf: false
            )
            newItem.user = context.isTrip ? newItemUser : nil
            modelContext.insert(newItem)
            list.addItem(newItem)

            newItemName = ""
            newItemCount = 1
        }
    }

    private func updateSingleListItem(_ item: Item, name: String, count: Int) {
        withAnimation {
            item.name = name
            item.count = count
            // Only clear if another row hasn't already taken over editing
            if singleListEditingItemId == item.persistentModelID {
                singleListEditingItemId = nil
            }
        }
    }

    private func saveListAsDefault(_ list: PackingList) {
        withAnimation {
            let newDefaultList = PackingList.copyAsTemplate(list)
            modelContext.insert(newDefaultList)
            isShowingSaveSuccessful = true
        }
    }
}
