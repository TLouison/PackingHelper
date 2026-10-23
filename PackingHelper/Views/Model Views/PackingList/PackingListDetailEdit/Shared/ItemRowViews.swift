//
//  ItemRowViews.swift
//  PackingHelper
//
//  Created by Todd Louison on 9/17/25.
//

import SwiftData
import SwiftUI

// MARK: - New Item Row

/// Inline Reminders-style row for adding an item directly inside a section.
/// Count and packer are edited from the accessory bar above the keyboard.
struct NewItemRow: View {
    @Binding var itemName: String
    @Binding var isFocused: Bool
    var itemCount: Int = 1
    var showsCheckbox: Bool = true

    let onSubmitReturn: () -> Void
    var onDeleteEmpty: (() -> Void)? = nil

    /// ScrollViewReader id for the new item row rendered inside a given list
    static func scrollID(for list: PackingList) -> String {
        "newItemRow-\(list.uuid.uuidString)"
    }

    var body: some View {
        HStack(spacing: 12) {
            if showsCheckbox {
                Image(systemName: "circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            } else {
                TemplateItemMarker()
            }

            PersistentTextField(
                text: $itemName,
                isFocused: $isFocused,
                placeholder: "New Item",
                textStyle: showsCheckbox ? .body : TemplateItemStyle.textStyle,
                onSubmit: onSubmitReturn,
                onDeleteBackwardWhenEmpty: onDeleteEmpty
            )

            if itemCount > 1 {
                ItemCountBadge(count: itemCount)
            }
        }
        .padding(.vertical, showsCheckbox ? 4 : TemplateItemStyle.verticalPadding)
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
    let isTemplating: Bool
    let onCommit: (String, Int) -> Void
    let onCancel: () -> Void
    var onDeleteEmpty: (() -> Void)? = nil

    @State private var editName: String
    @State private var editCount: Int
    @State private var isFocused = false
    @State private var didFinish = false

    init(
        item: Item,
        isTemplating: Bool,
        onCommit: @escaping (String, Int) -> Void,
        onCancel: @escaping () -> Void,
        onDeleteEmpty: (() -> Void)? = nil
    ) {
        self.item = item
        self.isTemplating = isTemplating
        self.onCommit = onCommit
        self.onCancel = onCancel
        self.onDeleteEmpty = onDeleteEmpty
        self._editName = State(initialValue: item.name)
        self._editCount = State(initialValue: item.count)
    }

    var body: some View {
        HStack(spacing: 12) {
            if !isTemplating {
                Image(
                    systemName: item.isPacked
                        ? "checkmark.circle.fill" : "circle"
                )
                .font(.title2)
                .foregroundStyle(item.isPacked ? Color.blue : Color.secondary)
            } else {
                TemplateItemMarker()
            }

            PersistentTextField(
                text: $editName,
                isFocused: $isFocused,
                placeholder: "Item name",
                textStyle: isTemplating ? TemplateItemStyle.textStyle : .body,
                onSubmit: finish,
                onDeleteBackwardWhenEmpty: onDeleteEmpty == nil ? nil : deleteEmpty
            )

            ItemCountStepper(count: $editCount)
        }
        .padding(.vertical, isTemplating ? TemplateItemStyle.verticalPadding : 4)
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

struct UnifiedItemRow: View {
    let item: Item
    let isTemplating: Bool
    let onTogglePacked: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    /// Set only when the item isn't in its section's template yet: shows the "New" pill and enables
    /// the leading "Add to Template" swipe (the caller confirms before saving)
    var onAddToTemplate: (() -> Void)? = nil

    @State private var offset: CGFloat = 0
    @State private var restingOffset: CGFloat = 0
    @State private var rowWidth: CGFloat = 0
    @State private var isDeleting = false

    /// Resting position when the delete action is revealed
    private let revealOffset: CGFloat = -72

    /// Resting position when the add-to-template action is revealed (reveal only, no full swipe)
    private let leadingRevealOffset: CGFloat = 72

    private var canAddToTemplate: Bool {
        onAddToTemplate != nil && !isTemplating
    }

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

            if canAddToTemplate {
                addToTemplateAction
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            rowContent
                .padding(.vertical, isTemplating ? TemplateItemStyle.verticalPadding : 4)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .offset(x: offset)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        .gesture(swipeGesture)
        .sensoryFeedback(.impact(weight: .medium), trigger: isPastFullSwipe) { _, isPast in isPast }
        .accessibilityAction(named: "Delete", onDelete)
        .accessibilityActions {
            if canAddToTemplate {
                Button("Add to Template", action: performAddToTemplate)
            }
        }
        .onChange(of: canAddToTemplate) { _, canAdd in
            // Saved elsewhere (e.g. a duplicate's swipe or the review sheet) while revealed
            if !canAdd && offset > 0 { closeSwipe() }
        }
        .onChange(of: item.isPacked) { _, _ in
            // Reset offset when item is packed/unpacked
            closeSwipe()
        }
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

    private var addToTemplateAction: some View {
        Button(action: performAddToTemplate) {
            Image(systemName: "square.and.arrow.down.on.square.fill")
                .font(.body)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .frame(width: max(0, offset))
        .background(Color.accentColor, in: .rect(cornerRadius: 10))
        .opacity(offset > 0 ? 1 : 0)
        .accessibilityHidden(true)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard !isDeleting,
                      abs(value.translation.width) > abs(value.translation.height)
                else { return }
                let proposed = restingOffset + value.translation.width
                if canAddToTemplate && proposed > 0 {
                    // Rubber-band past the reveal point; there's no full-swipe commit
                    offset = proposed <= leadingRevealOffset
                        ? proposed
                        : leadingRevealOffset + (proposed - leadingRevealOffset) * 0.25
                } else {
                    offset = min(0, proposed)
                }
            }
            .onEnded { _ in
                guard !isDeleting else { return }
                if offset > 0 {
                    withAnimation(.packingSpring) {
                        offset = offset > leadingRevealOffset / 2 ? leadingRevealOffset : 0
                    }
                    restingOffset = offset
                } else if isPastFullSwipe {
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

    private func performAddToTemplate() {
        closeSwipe()
        onAddToTemplate?()
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
            if !isTemplating {
                Button(action: onTogglePacked) {
                    Image(
                        systemName: item.isPacked
                            ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.title2)
                    .foregroundStyle(item.isPacked ? Color.blue : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    // Reach ~44pt without spacing the rows further apart
                    .contentShape(Rectangle().inset(by: -8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isPacked ? "Mark as unpacked" : "Mark as packed")
            } else {
                TemplateItemMarker()
            }

            Button {
                if offset != 0 {
                    closeSwipe()
                } else {
                    onEdit()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(isTemplating ? TemplateItemStyle.font : .body)
                        .strikethrough(item.isPacked)
                        .foregroundStyle(item.isPacked ? Color.secondary : Color.primary)

                    if canAddToTemplate {
                        Text("New")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: .capsule)
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityLabel("New, not in template")
                    }
                }
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
    var showsEmptyHint: Bool = false
    var minHeight: CGFloat = 28
    let action: () -> Void

    var body: some View {
        Group {
            if showsEmptyHint {
                Text("No items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityElement()
        .accessibilityLabel(showsEmptyHint ? "No items. Add item" : "Add item")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Packed Items Section

struct PackedItemsSection: View {
    let items: [Item]
    let onTogglePacked: (Item) -> Void
    let onDeleteItem: (Item) -> Void
    /// Items that aren't in their section's template yet
    var templateCandidateIDs: Set<PersistentIdentifier> = []
    var onAddToTemplate: ((Item) -> Void)? = nil
    var horizontalPadding: CGFloat = 16
    /// When false the section is always expanded and the header is not a toggle
    /// (used for the dedicated packed column in the wide layout)
    var isCollapsible: Bool = true

    @State private var isExpanded = false

    private var showsItems: Bool {
        !isCollapsible || isExpanded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isCollapsible {
                Button {
                    withAnimation(.packingSpring) {
                        isExpanded.toggle()
                    }
                } label: {
                    header
                }
                .buttonStyle(.plain)
            } else {
                header
            }

            if showsItems {
                VStack(spacing: 4) {
                    ForEach(items) { item in
                        UnifiedItemRow(
                            item: item,
                            isTemplating: false,
                            onTogglePacked: { onTogglePacked(item) },
                            onEdit: {},
                            onDelete: { onDeleteItem(item) },
                            onAddToTemplate: addToTemplateAction(for: item)
                        )
                    }
                }
            }
        }
    }

    private func addToTemplateAction(for item: Item) -> (() -> Void)? {
        guard let onAddToTemplate, templateCandidateIDs.contains(item.persistentModelID) else { return nil }
        return { onAddToTemplate(item) }
    }

    private var header: some View {
        HStack {
            Text("PACKED ITEMS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Spacer()

            Text("\(items.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isCollapsible {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 8)
    }
}

// MARK: - Wide Packing Layout

/// Regular width (iPhone Duo unfolded, iPad): packed items on the left half, available items on the right.
/// Each column scrolls independently.
///
/// An optional trailing panel sits just off the right edge. When `isShowingTrailing` is true the
/// whole strip slides left by one column, so the trailing panel pushes the packed column off screen
/// and leaves available | trailing visible.
struct WidePackingColumns<Packed: View, Available: View, Trailing: View>: View {
    var isShowingTrailing: Bool = false
    @ViewBuilder let packed: Packed
    @ViewBuilder let available: Available
    @ViewBuilder let trailing: Trailing

    var body: some View {
        GeometryReader { proxy in
            let columnWidth = proxy.size.width / 2

            HStack(spacing: 0) {
                ScrollView {
                    packed
                        .padding(.vertical)
                        .padding(.horizontal, 8)
                }
                .frame(width: columnWidth)
                .overlay(alignment: .trailing) { Divider() }
                .allowsHitTesting(!isShowingTrailing)
                .accessibilityHidden(isShowingTrailing)

                ScrollView {
                    available
                        .padding(.vertical)
                        .padding(.horizontal, 8)
                }
                .frame(width: columnWidth)
                .overlay(alignment: .trailing) { Divider() }

                trailing
                    .frame(width: columnWidth)
                    .allowsHitTesting(isShowingTrailing)
                    .accessibilityHidden(!isShowingTrailing)
            }
            .offset(x: isShowingTrailing ? -columnWidth : 0)
        }
        .clipped()
        .scrollDismissesKeyboard(.interactively)
    }
}

extension WidePackingColumns where Trailing == EmptyView {
    init(@ViewBuilder packed: () -> Packed, @ViewBuilder available: () -> Available) {
        self.packed = packed()
        self.available = available()
        self.trailing = EmptyView()
    }
}

/// Placeholder for the packed column before anything has been packed
struct NothingPackedView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44))
                .foregroundStyle(.gray.opacity(0.3))

            Text("Packed items will appear here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}
