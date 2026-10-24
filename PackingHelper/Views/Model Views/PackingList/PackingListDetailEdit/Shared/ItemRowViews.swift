//
//  ItemRowViews.swift
//  PackingHelper
//
//  Created by Todd Louison on 9/17/25.
//

import SwiftData
import SwiftUI

// MARK: - New Item Row

/// Inline Reminders-style row for adding an item to a template.
/// Count is edited from the accessory bar above the keyboard.
struct NewItemRow: View {
    @Binding var itemName: String
    @Binding var isFocused: Bool
    var itemCount: Int = 1

    let onSubmitReturn: () -> Void
    var onDeleteEmpty: (() -> Void)? = nil

    /// ScrollViewReader id for the new item row rendered inside a given list
    static func scrollID(for list: PackingList) -> String {
        "newItemRow-\(list.uuid.uuidString)"
    }

    var body: some View {
        HStack(spacing: 12) {
            TemplateItemMarker()

            PersistentTextField(
                text: $itemName,
                isFocused: $isFocused,
                placeholder: "New Item",
                textStyle: TemplateItemStyle.textStyle,
                onSubmit: onSubmitReturn,
                onDeleteBackwardWhenEmpty: onDeleteEmpty
            )

            if itemCount > 1 {
                ItemCountBadge(count: itemCount)
            }
        }
        .padding(.vertical, TemplateItemStyle.verticalPadding)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Template Item Styling

/// Template items aren't completable, so they get a dash instead of a checkbox and slightly
/// larger, roomier rows so each line still reads as its own entry
enum TemplateItemStyle {
    static let textStyle: UIFont.TextStyle = .title3
    static let font: Font = .title3
    static let verticalPadding: CGFloat = 10
}

/// Leading dash shown in place of the packed checkbox on template rows
struct TemplateItemMarker: View {
    var body: some View {
        Image(systemName: "minus")
            .font(.body.weight(.semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 24)
            .accessibilityHidden(true)
    }
}

// MARK: - Count Controls

struct ItemCountStepper: View {
    @Binding var count: Int

    @State private var countingDown = false

    var body: some View {
        HStack(spacing: 0) {
            Button {
                if count > 1 {
                    countingDown = true
                    withAnimation(.snappy) { count -= 1 }
                }
            } label: {
                Image(systemName: "minus")
                    .frame(width: 32, height: 32)
                    // 44pt hit area without making the capsule taller
                    .contentShape(Rectangle().inset(by: -6))
            }
            .disabled(count <= 1)
            .accessibilityLabel("Decrease count")
            Text("\(count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 24, alignment: .center)
                .contentTransition(.numericText(countsDown: countingDown))
            Button {
                if count < 99 {
                    countingDown = false
                    withAnimation(.snappy) { count += 1 }
                }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 32, height: 32)
                    // 44pt hit area without making the capsule taller
                    .contentShape(Rectangle().inset(by: -6))
            }
            .disabled(count >= 99)
            .accessibilityLabel("Increase count")
        }
        .buttonStyle(.borderless)
    }
}

struct ItemCountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.blue)
            .clipShape(.rect(cornerRadius: 10))
    }
}

// MARK: - Editable Item Row

/// Inline edit row. Commits on Return or when focus leaves the row; an empty name reverts.
/// Backspace on an empty name deletes the item.
struct EditableItemRow: View {
    let item: Item
    let onCommit: (String, Int) -> Void
    let onCancel: () -> Void
    var onDeleteEmpty: (() -> Void)? = nil

    @State private var editName: String
    @State private var editCount: Int
    @State private var isFocused = false
    @State private var didFinish = false

    init(
        item: Item,
        onCommit: @escaping (String, Int) -> Void,
        onCancel: @escaping () -> Void,
        onDeleteEmpty: (() -> Void)? = nil
    ) {
        self.item = item
        self.onCommit = onCommit
        self.onCancel = onCancel
        self.onDeleteEmpty = onDeleteEmpty
        self._editName = State(initialValue: item.name)
        self._editCount = State(initialValue: item.count)
    }

    var body: some View {
        HStack(spacing: 12) {
            TemplateItemMarker()

            PersistentTextField(
                text: $editName,
                isFocused: $isFocused,
                placeholder: "Item name",
                textStyle: TemplateItemStyle.textStyle,
                onSubmit: finish,
                onDeleteBackwardWhenEmpty: onDeleteEmpty == nil ? nil : deleteEmpty
            )

            ItemCountStepper(count: $editCount)
        }
        .padding(.vertical, TemplateItemStyle.verticalPadding)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemGroupedBackground))
                .padding(.vertical, -3)
        }
        .onAppear {
            isFocused = true
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { finish() }
        }
        .onDisappear {
            // Row can be torn down without losing focus first (e.g. tapping another row)
            finish()
        }
    }

    private func deleteEmpty() {
        guard !didFinish else { return }
        didFinish = true
        onDeleteEmpty?()
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        if editName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onCancel()
        } else {
            onCommit(editName, editCount)
        }
    }
}

// MARK: - Item Row

/// Template item: tap to edit, swipe to reveal delete, full swipe to delete
struct UnifiedItemRow: View {
    let item: Item
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var restingOffset: CGFloat = 0
    @State private var rowWidth: CGFloat = 0
    @State private var isDeleting = false

    /// Resting position when the delete action is revealed
    private let revealOffset: CGFloat = -72

    /// Swiping past this point deletes on release (Reminders-style full swipe)
    private var fullSwipeThreshold: CGFloat {
        -max(rowWidth * 0.55, 140)
    }

    private var isPastFullSwipe: Bool {
        offset < fullSwipeThreshold
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteAction

            rowContent
                .padding(.vertical, TemplateItemStyle.verticalPadding)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .offset(x: offset)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        .gesture(swipeGesture)
        .sensoryFeedback(.impact(weight: .medium), trigger: isPastFullSwipe) { _, isPast in isPast }
        .accessibilityAction(named: "Delete", onDelete)
        .onChange(of: item.id) { _, _ in
            // Reset offset when item changes (e.g., after adding)
            offset = 0
            restingOffset = 0
            isDeleting = false
        }
    }

    private var deleteAction: some View {
        Button(action: performDelete) {
            Image(systemName: "trash.fill")
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: isPastFullSwipe ? .leading : .center
                )
                .animation(.packingSpring, value: isPastFullSwipe)
        }
        .buttonStyle(.plain)
        .frame(width: max(0, -offset))
        .background(Color.red, in: .rect(cornerRadius: 10))
        .opacity(offset < 0 ? 1 : 0)
        .accessibilityHidden(true)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard !isDeleting,
                      abs(value.translation.width) > abs(value.translation.height)
                else { return }
                offset = min(0, restingOffset + value.translation.width)
            }
            .onEnded { _ in
                guard !isDeleting else { return }
                if isPastFullSwipe {
                    performDelete()
                } else {
                    withAnimation(.packingSpring) {
                        offset = offset < revealOffset / 2 ? revealOffset : 0
                    }
                    restingOffset = offset
                }
            }
    }

    private func closeSwipe() {
        withAnimation(.packingSpring) {
            offset = 0
        }
        restingOffset = 0
    }

    private func performDelete() {
        guard !isDeleting else { return }
        isDeleting = true
        withAnimation(.easeOut(duration: 0.2)) {
            offset = -max(rowWidth, 320)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDelete()
        }
    }

    var rowContent: some View {
        HStack(spacing: 12) {
            TemplateItemMarker()

            Button {
                if offset != 0 {
                    closeSwipe()
                } else {
                    onEdit()
                }
            } label: {
                Text(item.name)
                    .font(TemplateItemStyle.font)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if item.count > 1 {
                ItemCountBadge(count: item.count)
            }
        }
    }
}

// MARK: - Add Item Tap Zone

/// Blank area at the end of a section; tapping it starts adding an item there (Reminders-style)
struct AddItemTapZone: View {
    var minHeight: CGFloat = 28
    let action: () -> Void

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityElement()
            .accessibilityLabel("Add item")
            .accessibilityAddTraits(.isButton)
    }
}
