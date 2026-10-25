//
//  PackingListContainerView.swift
//  PackingHelper
//
//  Container that renders the packing screen.
//  Trip context: FocusPackingView (one page per section, swipe between).
//  Single-list context: inline template editor.
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let context: PackingListContext
    let users: [User]?
    let title: String?

    @State private var editingList: PackingList? = nil
    @State private var listToDelete: PackingList? = nil
    @State private var showingAddListSheet: Bool = false
    @State private var isApplyingDefaultPackingList: Bool = false
    @State private var isAddingNewItem: Bool = false
    @State private var selectedUser: User?

    // Remove Items mode (trip context): tap a card's minus to delete it right away
    @State private var isRemovingItems: Bool = false
    /// Items deleted in Remove Items mode, newest last; Undo puts back the last one
    @State private var removedItems: [RemovedItem] = []

    // AI assistant (trip context only)
    @State private var showingAIAssistant: Bool = false
    @State private var showingAIPaywall: Bool = false
    /// Show the paywall once the assistant sheet finishes dismissing (two
    /// sheets can't present back-to-back in the same update).
    @State private var showPaywallAfterAIDismiss: Bool = false
    /// Regular width: the assistant is a side panel instead of a sheet. `isShowingAssistantPanel`
    /// drives the slide; `isAssistantPanelMounted` keeps the chat rendered until the slide-out finishes.
    @State private var isShowingAssistantPanel: Bool = false
    @State private var isAssistantPanelMounted: Bool = false
    /// Shared by the panel and the sheet so the conversation survives a wide → compact switch.
    /// Replaced on each fresh open.
    @State private var assistantViewModel = AIAssistantViewModel()

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
    @State private var isDeleted: Bool = false

    // Single list mode item editing (trip context manages this inside FocusPackingView)
    @State private var singleListEditingItemId: PersistentIdentifier? = nil

    // MARK: - Initializers

    /// Initialize with a template
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

    /// Whether to show the user selector
    private var showUserSelector: Bool {
        context.isTrip && hasMultiplePackers
    }

    private var baseView: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            packingListView
        }
        .safeAreaInset(edge: .bottom) {
            if isAddingNewItem {
                newItemAccessoryBar
            }
        }
        .navigationTitle(title ?? "Packing")
        .navigationBarTitleDisplayMode(context.isTrip ? .inline : .large)
        .sheet(item: $editingList) { list in
            if let trip = context.trip {
                PackingListEditView(
                    packingList: list,
                    trip: trip,
                    isDeleted: .constant(false),
                    fitsContent: true
                )
            }
        }
        .sheet(isPresented: $showingAddListSheet) {
            if let trip = context.trip {
                PackingListEditView(
                    packingList: nil,
                    trip: trip,
                    onListCreated: { newList in
                        newItemList = newList
                    }, isDeleted: .constant(false),
                    fitsContent: true
                )
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
                    viewModel: assistantViewModel,
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
        .alert(
            "Delete \(listToDelete?.name ?? "Section")?",
            isPresented: Binding(get: { listToDelete != nil }, set: { if !$0 { listToDelete = nil } }),
            presenting: listToDelete
        ) { list in
            Button("Delete", role: .destructive) {
                withAnimation(.packingSpring) {
                    PackingList.delete(list, from: modelContext)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { list in
            let count = list.items?.count ?? 0
            if list.appliedFromTemplate != nil {
                Text("\(count) \(pluralizeString("item", count: count)) will be removed from this trip. The template it was applied from won't change.")
            } else {
                Text("\(count) \(pluralizeString("item", count: count)) will be removed from this trip.")
            }
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
        .sensoryFeedback(.impact(weight: .light), trigger: removedItems.count)
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
        .onChange(of: horizontalSizeClass) { _, sizeClass in
            // The panel only exists in the wide layout (e.g. the Duo was folded closed):
            // hand the open conversation over to the sheet instead of dropping it
            if sizeClass != .regular && isAssistantPanelMounted {
                isShowingAssistantPanel = false
                isAssistantPanelMounted = false
                showingAIAssistant = true
            } else if sizeClass == .regular && showingAIAssistant && context.isTrip {
                // Unfolded with the sheet open: move the conversation back into the side panel.
                // Shown in place (no slide) since the whole layout is already changing.
                showingAIAssistant = false
                isAssistantPanelMounted = true
                isShowingAssistantPanel = true
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
        lists.first(where: { $0.isDefault }) ?? sortedLists.first
    }

    /// Lists in the same order as the sections in `FocusPackingView`
    private var sortedLists: [PackingList] {
        PackingList.sorted(lists, sortOrder: .byCustomOrder)
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
            ForEach(sortedLists, id: \.id) { list in
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
        // Menus opening upward from the bottom reverse their items by default; keep section order
        .menuOrder(.fixed)
        .disabled(lists.count <= 1)
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

            if let trip = context.trip {
                tripPackingView(trip: trip)
            } else if let singleList = context.singleList {
                singleListView(list: singleList)
            }
        }
    }

    @ViewBuilder
    private func assistantPanel(trip: Trip) -> some View {
        if isAssistantPanelMounted {
            AIAssistantSheet(
                viewModel: assistantViewModel,
                trip: trip,
                users: users,
                targetUser: $newItemUser,
                onSubscriptionLapsed: {
                    closeAssistantPanel()
                    showingAIPaywall = true
                },
                onClose: closeAssistantPanel
            )
        }
    }

    // MARK: - Trip Packing

    private func tripPackingInput(trip: Trip) -> FocusPackingInput {
        FocusPackingInput(
            trip: trip,
            lists: sortedLists,
            users: users,
            selectedUser: selectedUser,
            add: PackingAddFlow(
                isAdding: isAddingNewItem,
                targetList: $newItemList,
                name: $newItemName,
                isFocused: $newItemFieldFocused,
                count: newItemCount,
                submit: addNewItemAndContinue,
                start: startAddingNewItem(in:),
                tapEmpty: handleTapOnEmptyArea(in:)
            ),
            onEditList: { editingList = $0 },
            onCreateList: { showingAddListSheet = true },
            onApplyTemplate: { isApplyingDefaultPackingList = true },
            onDeleteList: { listToDelete = $0 },
            isRemovingItems: isRemovingItems,
            onStartRemovingItems: startRemovingItems,
            onRemoveItem: removeItem
        )
    }

    /// Regular width: the AI panel takes the right half when open
    @ViewBuilder
    private func tripPackingView(trip: Trip) -> some View {
        // One structure for both size classes so FocusPackingView keeps its identity (and the page
        // it's on) when the Duo unfolds; only the panel beside it is conditional
        GeometryReader { proxy in
            HStack(spacing: 0) {
                FocusPackingView(input: tripPackingInput(trip: trip))
                    .frame(maxWidth: .infinity)

                if horizontalSizeClass == .regular {
                    assistantPanel(trip: trip)
                        .frame(width: isShowingAssistantPanel ? proxy.size.width / 2 : 0)
                        .clipped()
                        .overlay(alignment: .leading) { Divider() }
                        .allowsHitTesting(isShowingAssistantPanel)
                        .accessibilityHidden(!isShowingAssistantPanel)
                }
            }
        }
    }

    private func singleListView(list: PackingList) -> some View {
        let items = Item.sorted(list.items ?? [], sortOrder: .byCustomOrder)

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    singleListContent(list: list, items: items)
                    singleListTapZone
                }
                // Template rows already carry their own inset and roomier padding
                .padding(4)
            }
            .scrollDismissesKeyboard(.interactively)
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

    /// Item rows, inline new item row, and empty state for a template
    @ViewBuilder
    private func singleListContent(list: PackingList, items: [Item]) -> some View {
        ReorderableItemsSection(
            items: items,
            editingItemId: $singleListEditingItemId,
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

        if isAddingNewItem {
            NewItemRow(
                itemName: $newItemName,
                isFocused: $newItemFieldFocused,
                itemCount: newItemCount,
                onSubmitReturn: addNewItemAndContinue,
                onDeleteEmpty: {
                    // Backspace on the empty new row moves editing up to the last item
                    if let lastItem = items.last {
                        singleListEditingItemId = lastItem.persistentModelID
                    }
                }
            )
            .id(NewItemRow.scrollID(for: list))
        }

        if items.isEmpty && !isAddingNewItem {
            EmptyStateView()
                .padding(.top, 60)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { handleTapOnEmptyArea(in: nil) }
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
        if isRemovingItems {
            removingItemsToolbar
        } else if isAddingNewItem {
            addingItemToolbar
        } else if context.isTrip {
            tripToolbar
            addItemToolbar
        } else {
            singleListToolbar
            addItemToolbar
        }
    }

    /// Primary action lives in the bottom bar; on the folded iPhone Duo the system moves it to the side bar
    @ToolbarContentBuilder
    private var addItemToolbar: some ToolbarContent {
        // A trip with no sections has nowhere to put an item: create or apply one first
        if !(context.isTrip && lists.isEmpty) {
            ToolbarSpacer(placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button("Add Item", systemImage: "plus") {
                    startAddingNewItem(in: nil)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var addingItemToolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            // Title + symbol so the system has a name to show in overflow menus and expanded bars
            Button { finishAddingNewItem() } label: {
                Label("Done", systemImage: "checkmark")
                    .fontWeight(.semibold)
            }
        }
    }

    @ToolbarContentBuilder
    private var removingItemsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Undo", systemImage: "arrow.uturn.backward", action: undoRemoveItem)
                .disabled(removedItems.isEmpty)
                .accessibilityHint(removedItems.last.map { "Puts back \($0.name)" } ?? "")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button {
                withAnimation(.packingSpring) { isRemovingItems = false }
            } label: {
                Label("Done", systemImage: "checkmark")
                    .fontWeight(.semibold)
            }
        }
    }

    @ToolbarContentBuilder
    private var tripToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                if !purchaseManager.hasUnlockedPlus {
                    showingAIPaywall = true
                } else if horizontalSizeClass == .regular {
                    if isShowingAssistantPanel {
                        closeAssistantPanel()
                    } else {
                        openAssistantPanel()
                    }
                } else {
                    assistantViewModel = AIAssistantViewModel()
                    showingAIAssistant = true
                }
            } label: {
                Label {
                    Text("AI Packing Assistant")
                } icon: {
                    Image(systemName: "sparkles")
                        .overlay(alignment: .topTrailing) {
                            if !purchaseManager.hasUnlockedPlus {
                                Image(systemName: "plus.circle.fill")
                                    .font(.caption2)
                                    .imageScale(.small)
                                    .foregroundStyle(.white, .blue)
                                    .offset(x: 6, y: -6)
                                    .accessibilityHidden(true)
                            }
                        }
                }
            }
            .accessibilityHint(purchaseManager.hasUnlockedPlus ? "" : "Requires Packing Helper Plus")
        }
    }

    @ToolbarContentBuilder
    private var singleListToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isShowingTemplateInfo.toggle()
            } label: {
                Label("List Info", systemImage: "info.circle")
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

    // MARK: - Assistant Panel

    /// Reduce Motion swaps the panel slide for an instant change
    private var assistantPanelAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.45)
    }

    /// Slides the assistant in from the right, pushing the packed column off the left edge
    private func openAssistantPanel() {
        // Reopened mid-slide-out: keep the conversation that's still on screen
        if !isAssistantPanelMounted {
            assistantViewModel = AIAssistantViewModel()
        }
        isAssistantPanelMounted = true
        withAnimation(assistantPanelAnimation) {
            isShowingAssistantPanel = true
        }
    }

    private func closeAssistantPanel() {
        withAnimation(assistantPanelAnimation) {
            isShowingAssistantPanel = false
        } completion: {
            // Reopened mid-slide: keep the chat
            if !isShowingAssistantPanel {
                isAssistantPanelMounted = false
            }
        }
    }

    // MARK: - Add Item Actions

    /// Shows the inline new item row in `list` (or the current target list) and focuses it
    private func startAddingNewItem(in list: PackingList?) {
        // Items need a section; with none, the Add a Section page is the way forward
        guard !(context.isTrip && lists.isEmpty) else { return }
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

    // MARK: - Remove Items Actions

    private func startRemovingItems() {
        if isAddingNewItem {
            finishAddingNewItem()
        }
        withAnimation(.packingSpring) { isRemovingItems = true }
    }

    private func removeItem(_ item: Item) {
        if let removed = RemovedItem(item) {
            removedItems.append(removed)
        }
        withAnimation(.packingSpring) { modelContext.delete(item) }
    }

    /// Puts back the most recently removed item whose section still exists
    private func undoRemoveItem() {
        while let removed = removedItems.popLast() {
            guard !removed.list.isDeleted,
                  lists.contains(where: { $0.persistentModelID == removed.list.persistentModelID })
            else { continue }
            withAnimation(.packingSpring) { removed.restore(in: modelContext) }
            return
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
}
