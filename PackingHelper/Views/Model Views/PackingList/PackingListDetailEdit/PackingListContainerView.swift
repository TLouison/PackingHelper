//
//  PackingListContainerView.swift
//  PackingHelper
//
//  Container that renders the packing screen.
//  Trip context: FocusPackingView (one page per section, swipe between).
//  Single-list context: TemplateListEditorView.
//  Editing state and actions live in PackingEditor; sheets, toolbar, and the AI panel are in
//  the PackingListContainerView+*.swift files.
//
//  Created by Claude on 1/11/26.
//

import SwiftData
import SwiftUI

// MARK: - Container View

struct PackingListContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    // The extensions in `PackingListContainerView+*.swift` read the members below, so these
    // are internal rather than private.
    @Environment(PurchaseManager.self) var purchaseManager
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    let context: PackingListContext
    let title: String?
    @State private var featureFlags = FeatureFlags.shared

    /// Add, Edit Mode, template editing, and check-off state (shared with the Focus pages)
    @State var editor: PackingEditor
    /// The one sheet showing, if any (see `PackingListContainerView+Sheets.swift`)
    @State var activeSheet: ActiveSheet?
    @State private var listToDelete: PackingList? = nil
    /// Trip list being saved as a new template (name asked in an alert)
    @State private var listToSaveAsTemplate: PackingList?
    @State private var newTemplateName = ""
    @State private var savedTemplateCount = 0
    @Query(sort: \User.created) private var allUsers: [User]
    @Query(filter: #Predicate<PackingList> { $0.template }) private var templates: [PackingList]
    @State private var selectedUser: User?

    // AI assistant
    /// Regular width: the assistant is a side panel instead of a sheet. `isShowingAssistantPanel`
    /// drives the slide; `isAssistantPanelMounted` keeps the chat rendered until the slide-out finishes.
    @State var isShowingAssistantPanel: Bool = false
    @State var isAssistantPanelMounted: Bool = false
    /// Shared by the panel and the sheet so the conversation survives a wide → compact switch.
    /// Kept across opens; it also saves the chat, so leaving the screen keeps it too.
    @State var assistantViewModel: AIAssistantViewModel

    // Single list mode state
    @State var isDeleted: Bool = false

    // MARK: - Initializers

    /// Initialize with a template
    init(packingList: PackingList) {
        self.context = .singleList(packingList)
        self.title = packingList.name
        _editor = State(initialValue: PackingEditor(context: .singleList(packingList)))
        _assistantViewModel = State(initialValue: AIAssistantViewModel(context: .singleList(packingList)))
    }

    /// Initialize with a trip
    init(trip: Trip, title: String?) {
        self.context = .trip(trip)
        self.title = title
        _editor = State(initialValue: PackingEditor(context: .trip(trip)))
        _assistantViewModel = State(initialValue: AIAssistantViewModel(context: .trip(trip)))
    }

    // MARK: - Computed Properties

    var lists: [PackingList] {
        editor.lists
    }

    /// Packers items can be assigned to: everyone, or just the main (first) packer
    /// while multiple packers is off. Templates have no packers.
    var users: [User] {
        guard context.isTrip else { return [] }
        return featureFlags.showingMultiplePackers ? allUsers : Array(allUsers.prefix(1))
    }

    private var hasMultiplePackers: Bool {
        users.count > 1
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
                NewItemAccessoryBar(isTrip: context.isTrip, hasMultiplePackers: hasMultiplePackers)
            }
        }
        // Outside the inset so the accessory bar and the pages both read the editor
        .environment(editor)
        .navigationTitle(title ?? "Packing")
        .navigationBarTitleDisplayMode(context.isTrip ? .inline : .large)
        .sheet(item: $activeSheet) { sheet in
            sheetContent(sheet)
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
        .sensoryFeedback(.impact(weight: .light), trigger: editor.removedBatches.count)
        .onAppear {
            editor.configure(modelContext: modelContext)
            // Only seed on first appearance so returning to this view keeps the user's picks
            if editor.user == nil {
                editor.user = selectedUser ?? users.first
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
            handleSizeClassChange(to: sizeClass)
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
                    users: users,
                    selectedUser: $selectedUser
                )
            }

            if let trip = context.trip {
                tripPackingView(trip: trip)
            } else if let singleList = context.singleList {
                TemplateListEditorView(list: singleList)
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
            onEditList: { activeSheet = .editList($0) },
            onCreateList: { activeSheet = .addList },
            onApplyTemplate: { activeSheet = .applyTemplate },
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
                    assistantPanel
                        .frame(width: isShowingAssistantPanel ? proxy.size.width / 2 : 0)
                        .clipped()
                        .overlay(alignment: .leading) { Divider() }
                        .allowsHitTesting(isShowingAssistantPanel)
                        .accessibilityHidden(!isShowingAssistantPanel)
                }
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
