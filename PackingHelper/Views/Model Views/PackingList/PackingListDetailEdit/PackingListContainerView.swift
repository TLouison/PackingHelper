//
//  PackingListContainerView.swift
//  PackingHelper
//
//  Container that renders the packing screen.
//  Trip context: FocusPackingView (one page per section, swipe between).
//  Single-list context: inline template editor.
//  Editing state and actions live in PackingEditor.
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

    /// Add, Remove Items, template editing, and check-off state (shared with the Focus pages)
    @State private var editor: PackingEditor
    @State private var editingList: PackingList? = nil
    @State private var showingAddListSheet: Bool = false
    @State private var isApplyingDefaultPackingList: Bool = false
    @State private var isShowingListSettings: Bool = false
    @State private var isShowingTemplateInfo: Bool = false
    @State private var showingAIAssistant: Bool = false
    @State private var showingAIPaywall: Bool = false
    @State private var listToDelete: PackingList? = nil
    /// Trip list being saved as a new template (name asked in an alert)
    @State private var listToSaveAsTemplate: PackingList?
    @State private var newTemplateName = ""
    @State private var savedTemplateCount = 0
    @Query(sort: \User.created) private var allUsers: [User]
    @Query(filter: #Predicate<PackingList> { $0.template }) private var templates: [PackingList]
    @State private var selectedUser: User?

    // AI assistant (trip context only)
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

    // Single list mode state
    @State private var isDeleted: Bool = false
    @State private var singleListScrollTask: Task<Void, Never>?

    // MARK: - Initializers

    /// Initialize with a template
    init(packingList: PackingList) {
        self.context = .singleList(packingList)
        self.users = nil
        self.title = packingList.name
        _editor = State(initialValue: PackingEditor(context: .singleList(packingList)))
    }

    /// Initialize with a trip
    init(trip: Trip, users: [User]?, title: String?) {
        self.context = .trip(trip)
        self.users = users
        self.title = title
        _editor = State(initialValue: PackingEditor(context: .trip(trip)))
    }

    // MARK: - Computed Properties

    private var lists: [PackingList] {
        editor.lists
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
            if editor.isAdding {
                newItemAccessoryBar
            }
        }
        // Outside the inset so the accessory bar and the pages both read the editor
        .environment(editor)
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
                        editor.targetList = newList
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
                    isDeleted: $isDeleted,
                    fitsContent: true
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
                    targetUser: Bindable(editor).user,
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
            "Delete \(listToDelete?.name ?? "List")?",
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
        .alert(
            "Save as Template",
            isPresented: Binding(get: { listToSaveAsTemplate != nil }, set: { if !$0 { listToSaveAsTemplate = nil } }),
            presenting: listToSaveAsTemplate
        ) { list in
            TextField("Template Name", text: $newTemplateName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveAsTemplate(list) }
                .disabled(newTemplateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: { _ in
            if PackingList.templateNameExists(newTemplateName, in: templates) {
                Text("Saves this list's items and counts so you can apply them to future trips.\n\nYou already have a template named \(newTemplateName). Saving makes a second one.")
            } else {
                Text("Saves this list's items and counts so you can apply them to future trips.")
            }
        }
        .sensoryFeedback(.success, trigger: savedTemplateCount)
        .onChange(of: isDeleted) {
            dismiss()
        }
        .onChange(of: editor.isFieldFocused) { _, isFocused in
            editor.focusChanged(to: isFocused)
        }
        .toolbar {
            containerToolbar
        }
        .sensoryFeedback(.impact(weight: .light), trigger: editor.removedItems.count)
        .onAppear {
            editor.configure(modelContext: modelContext)
            // Only seed on first appearance so returning to this view keeps the user's picks
            if editor.user == nil {
                editor.user = selectedUser ?? users?.first
            }
            editor.resetTargetListIfNeeded()
        }
        .onChange(of: selectedUser) { _, user in
            // Keep new items assigned to the packer being filtered on, otherwise they vanish on add
            if let user {
                editor.user = user
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
            editor.resetTargetListIfNeeded()
        }
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

    // MARK: - Trip Packing

    private func tripPackingInput(trip: Trip) -> FocusPackingInput {
        FocusPackingInput(
            trip: trip,
            lists: editor.sortedLists,
            users: users,
            selectedUser: selectedUser,
            onEditList: { editingList = $0 },
            onCreateList: { showingAddListSheet = true },
            onApplyTemplate: { isApplyingDefaultPackingList = true },
            onDeleteList: { listToDelete = $0 },
            onSaveAsTemplate: { list in
                newTemplateName = list.name
                listToSaveAsTemplate = list
            }
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

    // MARK: - Assistant Panel

    @ViewBuilder
    private func assistantPanel(trip: Trip) -> some View {
        if isAssistantPanelMounted {
            AIAssistantSheet(
                viewModel: assistantViewModel,
                trip: trip,
                users: users,
                targetUser: Bindable(editor).user,
                onSubscriptionLapsed: {
                    closeAssistantPanel()
                    showingAIPaywall = true
                },
                onClose: closeAssistantPanel
            )
        }
    }

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

    // MARK: - New Item Accessory Bar

    /// Sits directly above the keyboard while the inline new item row is focused
    private var newItemAccessoryBar: some View {
        HStack(spacing: 8) {
            if context.isTrip {
                listPickerMenu
            }

            if hasMultiplePackers {
                UserPickerView(
                    selectedUser: Bindable(editor).user,
                    style: .menu,
                    allowAll: false
                )
            }

            Spacer()

            ItemCountStepper(count: Bindable(editor).count)
                .padding(.horizontal, 4)
                .opaqueGlassCapsule()
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var listPickerMenu: some View {
        Menu {
            ForEach(editor.sortedLists, id: \.id) { list in
                Button {
                    editor.targetList = list
                } label: {
                    if list.id == editor.targetList?.id {
                        Label(list.name, systemImage: "checkmark")
                    } else {
                        ListMenuLabel(list: list)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet")
                    .font(.caption)
                Text(editor.resolvedTargetList?.name ?? "Select List")
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
        .disabled(editor.lists.count <= 1)
    }

    // MARK: - Single List

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
            .onChange(of: editor.isAdding) { _, isAdding in
                if isAdding {
                    withAnimation { proxy.scrollTo(NewItemRow.scrollID(for: list), anchor: .bottom) }
                }
            }
            .onChange(of: editor.scrollToPlaceholder) { _, shouldScroll in
                guard shouldScroll else { return }
                editor.scrollToPlaceholder = false
                singleListScrollTask?.cancel()
                singleListScrollTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
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
            editingItemId: Bindable(editor).editingItemId,
            onUpdateItem: { editor.updateItem($0, name: $1, count: $2) },
            onDeleteItem: { editor.deleteItem($0) },
            onReorder: { item, newIndex in
                editor.reorderItem(item, in: list, to: newIndex)
            }
        )

        if editor.isAdding {
            NewItemRow(
                itemName: Bindable(editor).name,
                isFocused: Bindable(editor).isFieldFocused,
                itemCount: editor.count,
                onSubmitReturn: { editor.addAndContinue() },
                onDeleteEmpty: {
                    // Backspace on the empty new row moves editing up to the last item
                    if let lastItem = items.last {
                        editor.editingItemId = lastItem.persistentModelID
                    }
                }
            )
            .id(NewItemRow.scrollID(for: list))
        }

        if items.isEmpty && !editor.isAdding {
            EmptyStateView()
                .padding(.top, 60)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { editor.handleTapOnEmptyArea(in: nil) }
        }
    }

    /// Blank space below the list: tap to add, or to finish adding
    private var singleListTapZone: some View {
        AddItemTapZone(minHeight: 120) {
            editor.handleTapOnEmptyArea(in: nil)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var containerToolbar: some ToolbarContent {
        if editor.isRemovingItems {
            removingItemsToolbar
        } else if editor.isAdding {
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
                    editor.startAdding(in: nil)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var addingItemToolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            // Title + symbol so the system has a name to show in overflow menus and expanded bars
            Button { editor.finishAdding() } label: {
                Label("Done", systemImage: "checkmark")
                    .fontWeight(.semibold)
            }
        }
    }

    @ToolbarContentBuilder
    private var removingItemsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Undo", systemImage: "arrow.uturn.backward", action: editor.undoRemove)
                .disabled(editor.removedItems.isEmpty)
                .accessibilityHint(editor.removedItems.last.map { "Puts back \($0.name)" } ?? "")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button {
                editor.stopRemoving()
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
                if !purchaseManager.isPlusActive {
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
                            if !purchaseManager.isPlusActive {
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
            .accessibilityHint(purchaseManager.isPlusActive ? "" : "Requires Packing Helper Plus")
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

    /// Copies the list's names and counts into a new template and links the list to it
    private func saveAsTemplate(_ list: PackingList) {
        let name = newTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, list.isNewTemplateCandidate else { return }
        list.saveAsNewTemplate(named: name, owner: allUsers.first, in: modelContext)
        try? modelContext.save()
        savedTemplateCount += 1
    }
}
