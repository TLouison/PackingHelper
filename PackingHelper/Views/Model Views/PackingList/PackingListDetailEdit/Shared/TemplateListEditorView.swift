//
//  TemplateListEditorView.swift
//  PackingHelper
//
//  Inline editor for a single template list: Reminders-style rows, drag to reorder, and a
//  tap zone below to add. State and actions live in `PackingEditor`.
//

import SwiftData
import SwiftUI

struct TemplateListEditorView: View {
    @Environment(PackingEditor.self) private var editor

    let list: PackingList

    @State private var scrollTask: Task<Void, Never>?

    var body: some View {
        let items = Item.sorted(list.items ?? [], sortOrder: .byCustomOrder)

        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    content(items: items)
                    tapZone
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
                scrollTask?.cancel()
                scrollTask = Task { @MainActor in
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
    private func content(items: [Item]) -> some View {
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
    private var tapZone: some View {
        AddItemTapZone(minHeight: 120) {
            editor.handleTapOnEmptyArea(in: nil)
        }
    }
}
