//
//  RemindersPackingView.swift
//  PackingHelper
//
//  Prototype: a close mirror of Apple Reminders. One plain list, bold section headers,
//  ring checkboxes, packed items hidden by default ("N Packed · Show"), tap a row to rename
//  in place with an info button for details, tap blank space at a section's end to add there,
//  native swipe actions and long-press drag to reorder.
//

import SwiftData
import SwiftUI

struct RemindersPackingView: View {
    @Environment(\.modelContext) private var modelContext

    let input: PackingPrototypeInput

    /// Reminders hides completed items until you ask to see them
    @AppStorage("remindersShowPacked") private var showPacked = false
    @State private var pendingPacks = PendingPackTracker()
    @State private var editingItemID: PersistentIdentifier?
    @State private var detailItem: Item?

    private var allItems: [Item] {
        input.lists.flatMap(input.items(in:))
    }

    var body: some View {
        let allItems = self.allItems
        let packedCount = allItems.filter(\.isPacked).count

        ScrollViewReader { proxy in
            List {
                packedSummary(packed: packedCount, total: allItems.count)

                ForEach(input.lists) { list in
                    let sectionRows = rows(in: list)
                    Section {
                        ForEach(sectionRows) { item in
                            RemindersItemRow(
                                item: item,
                                showsPacker: input.hasMultiplePackers,
                                isEditing: editingItemID == item.persistentModelID,
                                onToggle: { toggle(item) },
                                onBeginEditing: { beginEditing(item) },
                                onCommit: { commit(item, name: $0) },
                                onReturn: { input.add.start(list) },
                                onShowDetails: { detailItem = item },
                                onDelete: { delete(item) }
                            )
                        }
                        .onMove { source, destination in
                            withAnimation(.packingSpring) {
                                PrototypeItemActions.move(sectionRows, from: source, to: destination, in: list)
                            }
                        }

                        addRow(for: list, isEmpty: sectionRows.isEmpty)
                    } header: {
                        sectionHeader(list)
                    }
                }

                if allItems.isEmpty && !input.add.isAdding {
                    EmptyStateView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                // Blank space below everything: tap to add to the current section, or to finish adding
                Color.clear
                    .frame(height: 200)
                    .contentShape(Rectangle())
                    .onTapGesture { input.add.tapEmpty(nil) }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .accessibilityHidden(true)
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: input.add.isAdding) { _, isAdding in
                if isAdding {
                    editingItemID = nil
                    scrollToNewRow(proxy)
                }
            }
            .onChange(of: input.add.targetList.wrappedValue?.persistentModelID) {
                if input.add.isAdding { scrollToNewRow(proxy) }
            }
            .onChange(of: allItems.count) {
                // Return added an item: keep the new row above the keyboard
                if input.add.isAdding { scrollToNewRow(proxy) }
            }
        }
        .sheet(item: $detailItem) { item in
            PrototypeItemDetailSheet(item: item, lists: input.lists, users: input.users)
        }
    }

    // MARK: - Rows

    private func rows(in list: PackingList) -> [Item] {
        let items = input.items(in: list)
        return showPacked ? items : pendingPacks.visibleUnpacked(items)
    }

    /// "12 of 30 Packed · Show", Reminders' "3 Completed · Clear   Show" bar
    private func packedSummary(packed: Int, total: Int) -> some View {
        HStack {
            Text(total == 0 ? "Nothing to pack yet" : "\(packed) of \(total) Packed")
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.snappy, value: packed)

            Spacer()

            if packed > 0 {
                Button(showPacked ? "Hide" : "Show") {
                    withAnimation(.packingSpring) { showPacked.toggle() }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(showPacked ? "Hide Packed Items" : "Show Packed Items")
            }
        }
        .font(.subheadline)
        .listRowSeparator(.hidden)
        .moveDisabled(true)
    }

    private func sectionHeader(_ list: PackingList) -> some View {
        Text(list.name)
            .font(.title3.bold())
            .foregroundStyle(.primary)
            .textCase(nil)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { input.onEditList(list) }
            .contextMenu {
                Button("New Item", systemImage: "plus") { input.add.start(list) }
                Button("Edit Section", systemImage: "pencil") { input.onEditList(list) }
            }
            .accessibilityAddTraits([.isHeader, .isButton])
            .accessibilityHint("Edits the section")
    }

    /// The inline new item row in the target section, otherwise a blank row that starts one
    @ViewBuilder
    private func addRow(for list: PackingList, isEmpty: Bool) -> some View {
        if input.add.isTarget(list) {
            HStack(spacing: 12) {
                PackCheckbox(isPacked: false)
                    .opacity(0.6)
                PersistentTextField(
                    text: input.add.name,
                    isFocused: input.add.isFocused,
                    placeholder: "New Item",
                    onSubmit: input.add.submit
                )
                if input.add.count > 1 {
                    Text("×\(input.add.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 4)
            .id(NewItemRow.scrollID(for: list))
            .moveDisabled(true)
        } else {
            Text(isEmpty ? "No Items" : " ")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { input.add.tapEmpty(list) }
                .listRowSeparator(.hidden)
                .moveDisabled(true)
                .accessibilityElement()
                .accessibilityLabel("Add Item to \(list.name)")
                .accessibilityAddTraits(.isButton)
        }
    }

    private func scrollToNewRow(_ proxy: ScrollViewProxy) {
        guard let target = input.add.targetList.wrappedValue else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                proxy.scrollTo(NewItemRow.scrollID(for: target), anchor: .bottom)
            }
        }
    }

    // MARK: - Actions

    private func toggle(_ item: Item) {
        if showPacked {
            // Shown packed items stay in place, so there's nothing to delay
            withAnimation(.snappy) { item.isPacked.toggle() }
        } else {
            pendingPacks.toggle(item)
        }
    }

    private func beginEditing(_ item: Item) {
        if input.add.isAdding {
            input.add.tapEmpty(nil)
        }
        editingItemID = item.persistentModelID
    }

    /// Reminders deletes a reminder whose title is cleared
    private func commit(_ item: Item, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if editingItemID == item.persistentModelID {
            editingItemID = nil
        }
        guard !item.isDeleted else { return }
        if trimmed.isEmpty {
            delete(item)
        } else if trimmed != item.name {
            item.name = trimmed
        }
    }

    private func delete(_ item: Item) {
        withAnimation(.packingSpring) {
            modelContext.delete(item)
        }
    }
}

// MARK: - Row

private struct RemindersItemRow: View {
    let item: Item
    let showsPacker: Bool
    let isEditing: Bool
    let onToggle: () -> Void
    let onBeginEditing: () -> Void
    let onCommit: (String) -> Void
    let onReturn: () -> Void
    let onShowDetails: () -> Void
    let onDelete: () -> Void

    private var showsSubtitle: Bool {
        item.count > 1 || (showsPacker && item.user != nil)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                PackCheckbox(isPacked: item.isPacked)
                    // Reach ~44pt without spacing the rows further apart
                    .contentShape(Rectangle().inset(by: -10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isPacked ? "Mark as unpacked" : "Mark as packed")

            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    RemindersNameEditor(item: item, onCommit: onCommit, onReturn: onReturn)
                } else {
                    Text(item.name)
                        .foregroundStyle(item.isPacked ? .secondary : .primary)
                }

                if showsSubtitle {
                    subtitle
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // Off while renaming so taps reach the text field
            .gesture(TapGesture().onEnded(onBeginEditing), isEnabled: !isEditing)

            if isEditing {
                Button("Details", systemImage: "info.circle", action: onShowDetails)
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .buttonStyle(.borderless)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
        .animation(.snappy, value: isEditing)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            Button("Details", systemImage: "info.circle", action: onShowDetails)
                .tint(.gray)
        }
        // Keep the text field reachable while renaming
        .accessibilityElement(children: isEditing ? .contain : .combine)
        .accessibilityAction(named: item.isPacked ? "Mark as unpacked" : "Mark as packed", onToggle)
        .accessibilityAction(named: "Rename", onBeginEditing)
        .accessibilityAction(named: "Details", onShowDetails)
    }

    private var subtitle: some View {
        HStack(spacing: 6) {
            if item.count > 1 {
                Text("×\(item.count)")
                    .monospacedDigit()
            }
            if showsPacker, let user = item.user {
                Text(user.name)
                    .foregroundStyle(user.userColor)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}

/// In-place rename. Commits on Return, blur, or disappear; Return also starts a new item.
private struct RemindersNameEditor: View {
    let item: Item
    let onCommit: (String) -> Void
    let onReturn: () -> Void

    @State private var text: String
    @State private var isFocused = false
    @State private var didFinish = false

    init(item: Item, onCommit: @escaping (String) -> Void, onReturn: @escaping () -> Void) {
        self.item = item
        self.onCommit = onCommit
        self.onReturn = onReturn
        _text = State(initialValue: item.name)
    }

    var body: some View {
        PersistentTextField(
            text: $text,
            isFocused: $isFocused,
            placeholder: "Item",
            onSubmit: {
                finish()
                onReturn()
            }
        )
        .onAppear { isFocused = true }
        .onChange(of: isFocused) { _, focused in
            if !focused { finish() }
        }
        .onDisappear { finish() }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onCommit(text)
    }
}
