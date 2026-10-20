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
                floatingInputBar
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
        .sheet(isPresented: $showingAIAssistant) {
            if let trip = context.trip {
                AIAssistantSheet(
                    trip: trip,
                    users: users,
                    targetUser: $newItemUser,
                    targetList: $newItemList
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
            if !isFocused && isAddingNewItem {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    newItemName = ""
                    newItemCount = 1
                    isAddingNewItem = false
                }
            }
        }
        .toolbar {
            containerToolbar
        }
        .onAppear {
            newItemUser = users?.first
            newItemList = lists.first(where: { $0.isDefault }) ?? lists.first
        }
    }

    // MARK: - Floating Input Bar

    private var listPickerChips: some View {
        HStack(spacing: 8) {
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
                    Text(newItemList?.name ?? "Select List")
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

            if hasMultiplePackers {
                UserPickerView(
                    selectedUser: $newItemUser,
                    style: .menu,
                    allowAll: false
                )
            }

            Spacer()
        }
        .padding(.horizontal)
    }

    private var floatingInputBar: some View {
        VStack(spacing: 8) {
            if context.isTrip {
                listPickerChips
            }

            NewItemRow(
                itemName: $newItemName,
                itemCount: $newItemCount,
                isFocused: $newItemFieldFocused,
                onSubmitReturn: addNewItemAndContinue
            )
            .opaqueRoundedBox()
            .shaded()
            .padding(.horizontal, 8)
        }
        .padding(.bottom, 8)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.3, anchor: .bottomTrailing).combined(with: .opacity),
            removal: .scale(scale: 0.3, anchor: .bottomTrailing).combined(with: .opacity)
        ))
    }

    // MARK: - FAB Button

    private var fabButton: some View {
        Button(action: startAddingNewItem) {
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
                    scrollToPlaceholder: $scrollToPlaceholder
                )
            } else if let singleList = context.singleList {
                singleListView(list: singleList)
            }

            // Summary bar hidden when adding to prevent stacking with input bar
            if showSummaryBar && !isAddingNewItem {
                PackingSummaryBar(packingLists: lists)
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                if isAddingNewItem {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
            }
        )
    }

    @ViewBuilder
    private func singleListView(list: PackingList) -> some View {
        let allItems = Item.sorted(list.items ?? [], sortOrder: .byCustomOrder)
        let unpackedItems = Item.sorted(list.incompleteItems, sortOrder: .byCustomOrder)

        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if isTemplating {
                        ReorderableItemsSection(
                            items: allItems,
                            isTemplating: true,
                            editingItemId: $singleListEditingItemId,
                            onTogglePacked: { _ in },
                            onUpdateItem: { item, name, count in
                                withAnimation { item.name = name; item.count = count; singleListEditingItemId = nil }
                            },
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
                                withAnimation(.packingSpring) { item.isPacked.toggle() }
                            },
                            onUpdateItem: { item, name, count in
                                withAnimation { item.name = name; item.count = count; singleListEditingItemId = nil }
                            },
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
                        InsertionPlaceholder()
                            .id("insertionPlaceholder")
                    }

                    if allItems.isEmpty && !isAddingNewItem {
                        EmptyStateView()
                            .padding(.top, 60)
                    }

                    if !isTemplating {
                        let packedItems = Item.sorted(list.completeItems, sortOrder: .byCustomOrder)
                        if !packedItems.isEmpty {
                            PackedItemsSection(
                                items: packedItems,
                                onTogglePacked: { item in withAnimation(.packingSpring) { item.isPacked.toggle() } },
                                onDeleteItem: { item in withAnimation(.packingSpring) { modelContext.delete(item) } }
                            )
                        }
                    }
                }
                .padding()
            }
            .onChange(of: isAddingNewItem) { _, isAdding in
                if isAdding {
                    withAnimation { proxy.scrollTo("insertionPlaceholder", anchor: .bottom) }
                }
            }
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
            Button { addNewItemAndClose() } label: {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
            }
            .opacity(newItemName.isEmpty ? 0.3 : 1.0)
            .disabled(newItemName.isEmpty)
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

    private func startAddingNewItem() {
        newItemFieldFocused = true
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            isAddingNewItem = true
        }
    }

    private func addNewItemAndContinue() {
        guard let list = context.isTrip ? newItemList : context.singleList else { return }
        guard !newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        withAnimation(.packingSpring) {
            let newItem = Item(
                name: newItemName,
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

        scrollToPlaceholder = true
    }

    private func addNewItemAndClose() {
        let list = context.isTrip ? newItemList : context.singleList
        if !newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let list = list
        {
            withAnimation(.packingSpring) {
                let newItem = Item(
                    name: newItemName,
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
            }
        }

        newItemFieldFocused = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            newItemName = ""
            newItemCount = 1
            isAddingNewItem = false
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
