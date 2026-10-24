//
//  TilesPackingView.swift
//  PackingHelper
//
//  Prototype: every item is a tap-to-pack tile, wrapped densely per section so a whole
//  trip fits on one or two screens. Tap a tile to pack it (tap again within ~1.5s to undo),
//  long-press for count, packer, section, and delete. Packed tiles tuck away behind a
//  per-section "N packed" toggle, and a suitcase dock at the bottom fills as you go.
//

import SwiftData
import SwiftUI

struct TilesPackingView: View {
    @Environment(\.modelContext) private var modelContext

    let input: PackingPrototypeInput

    @State private var pendingPacks = PendingPackTracker()
    @State private var detailItem: Item?
    /// Sections currently showing their packed tiles
    @State private var revealedPacked: Set<PersistentIdentifier> = []

    var body: some View {
        let allItems = input.lists.flatMap(input.items(in:))
        let packedCount = allItems.filter(\.isPacked).count

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(input.lists) { list in
                        section(list)
                    }

                    if allItems.isEmpty && !input.add.isAdding {
                        EmptyStateView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }

                    // Blank space below everything: tap to add, or to finish adding
                    Color.clear
                        .frame(height: 160)
                        .contentShape(Rectangle())
                        .onTapGesture { input.add.tapEmpty(nil) }
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if !input.add.isAdding && !allItems.isEmpty {
                    SuitcaseDock(packed: packedCount, total: allItems.count)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onChange(of: input.add.isAdding) { _, isAdding in
                if isAdding { scrollToNewTile(proxy) }
            }
            .onChange(of: input.add.targetList.wrappedValue?.persistentModelID) {
                if input.add.isAdding { scrollToNewTile(proxy) }
            }
            .onChange(of: allItems.count) {
                if input.add.isAdding { scrollToNewTile(proxy) }
            }
        }
        .sheet(item: $detailItem) { item in
            PrototypeItemDetailSheet(item: item, lists: input.lists, users: input.users)
        }
    }

    // MARK: - Section

    @ViewBuilder
    private func section(_ list: PackingList) -> some View {
        let items = input.items(in: list)
        let unpacked = pendingPacks.visibleUnpacked(items)
        let packed = pendingPacks.settledPacked(items)
        let isRevealed = revealedPacked.contains(list.persistentModelID)

        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(list, items: items, packed: packed, isRevealed: isRevealed)

            TileFlowLayout(spacing: 8) {
                ForEach(unpacked) { item in
                    tile(for: item)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
                addTile(for: list)
            }
            .animation(.packingSpring, value: unpacked.map(\.persistentModelID))

            if isRevealed && !packed.isEmpty {
                TileFlowLayout(spacing: 6) {
                    ForEach(packed) { item in
                        tile(for: item, isCompact: true)
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func sectionHeader(_ list: PackingList, items: [Item], packed: [Item], isRevealed: Bool) -> some View {
        let packedCount = items.filter(\.isPacked).count
        let isComplete = !items.isEmpty && packedCount == items.count

        return HStack(spacing: 10) {
            ZStack {
                PackProgressRing(progress: items.packedFraction, lineWidth: 3, tint: isComplete ? .green : .accentColor)
                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.green)
                }
            }
            .frame(width: 22, height: 22)

            Text(list.name)
                .font(.title3.bold())
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            if !items.isEmpty {
                Text(isComplete ? "All packed" : "\(items.count - packedCount) left")
                    .font(.subheadline)
                    .foregroundStyle(isComplete ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)

            if !packed.isEmpty {
                Button {
                    withAnimation(.packingSpring) {
                        if isRevealed {
                            revealedPacked.remove(list.persistentModelID)
                        } else {
                            revealedPacked.insert(list.persistentModelID)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isRevealed ? "Hide" : "\(packed.count) packed")
                            .contentTransition(.numericText())
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(isRevealed ? 180 : 0))
                    }
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isRevealed ? "Hide packed items" : "Show \(packed.count) packed items")
            }
        }
        .animation(.snappy, value: packedCount)
        .contentShape(Rectangle())
        .contextMenu {
            Button("New Item", systemImage: "plus") { input.add.start(list) }
            Button("Edit Section", systemImage: "pencil") { input.onEditList(list) }
        }
    }

    // MARK: - Tiles

    private func tile(for item: Item, isCompact: Bool = false) -> some View {
        PackTile(
            item: item,
            isCompact: isCompact,
            showsPacker: input.hasMultiplePackers,
            lists: input.lists,
            users: input.users,
            onToggle: { pendingPacks.toggle(item) },
            onShowDetails: { detailItem = item },
            onChangeCount: { count in
                withAnimation(.snappy) { item.count = count }
            },
            onMove: { list in
                withAnimation(.packingSpring) { PrototypeItemActions.moveToList(item, list) }
            },
            onAssign: { user in
                withAnimation(.snappy) { item.user = user }
            },
            onDelete: {
                withAnimation(.packingSpring) { modelContext.delete(item) }
            }
        )
    }

    /// The inline new item tile in the target section, otherwise a dashed "Add" tile
    @ViewBuilder
    private func addTile(for list: PackingList) -> some View {
        if input.add.isTarget(list) {
            HStack(spacing: 6) {
                PersistentTextField(
                    text: input.add.name,
                    isFocused: input.add.isFocused,
                    placeholder: "New Item",
                    textStyle: .callout,
                    onSubmit: input.add.submit
                )
                if input.add.count > 1 {
                    Text("×\(input.add.count)")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 190)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
            .id(NewItemRow.scrollID(for: list))
        } else {
            Button {
                input.add.start(list)
            } label: {
                Label("Add", systemImage: "plus")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .foregroundStyle(.tint.opacity(0.45))
                    }
                    .contentShape(.rect(cornerRadius: 14))
            }
            .buttonStyle(PressableCardStyle(scale: 0.92))
            .accessibilityLabel("Add Item to \(list.name)")
        }
    }

    private func scrollToNewTile(_ proxy: ScrollViewProxy) {
        guard let target = input.add.targetList.wrappedValue else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                proxy.scrollTo(NewItemRow.scrollID(for: target), anchor: .center)
            }
        }
    }
}

// MARK: - Tile

private struct PackTile: View {
    let item: Item
    let isCompact: Bool
    let showsPacker: Bool
    let lists: [PackingList]
    let users: [User]?
    let onToggle: () -> Void
    let onShowDetails: () -> Void
    let onChangeCount: (Int) -> Void
    let onMove: (PackingList) -> Void
    let onAssign: (User?) -> Void
    let onDelete: () -> Void

    /// Just checked and still in place (pending), shown filled so the tap reads instantly
    private var isFilled: Bool {
        item.isPacked && !isCompact
    }

    private var foreground: Color {
        if isFilled { return .white }
        return isCompact ? .secondary : .primary
    }

    private var background: Color {
        if isFilled { return .accentColor }
        return isCompact ? Color(.tertiarySystemFill) : Color(.secondarySystemGroupedBackground)
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                if item.isPacked {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .transition(.scale.combined(with: .opacity))
                } else if showsPacker, let user = item.user {
                    Circle()
                        .fill(user.userColor)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }

                Text(item.name)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if item.count > 1 {
                    Text("×\(item.count)")
                        .monospacedDigit()
                        .opacity(0.7)
                        .contentTransition(.numericText())
                }
            }
            .font(isCompact ? .footnote : .callout.weight(.medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, isCompact ? 10 : 14)
            .padding(.vertical, isCompact ? 6 : 11)
            .background(background, in: .rect(cornerRadius: isCompact ? 10 : 14))
            .contentShape(.rect(cornerRadius: isCompact ? 10 : 14))
            .animation(.snappy(duration: 0.2), value: item.isPacked)
        }
        .buttonStyle(PressableCardStyle(scale: 0.92))
        .sensoryFeedback(.impact(weight: .light), trigger: item.isPacked)
        .contextMenu { menu }
        .accessibilityLabel(item.count > 1 ? "\(item.name), \(item.count)" : item.name)
        .accessibilityValue(item.isPacked ? "Packed" : "Not packed")
        .accessibilityHint(item.isPacked ? "Unpacks the item" : "Packs the item")
    }

    @ViewBuilder
    private var menu: some View {
        Button("Details", systemImage: "info.circle", action: onShowDetails)

        if item.count < 99 {
            Button("Add One", systemImage: "plus") { onChangeCount(item.count + 1) }
        }
        if item.count > 1 {
            Button("Remove One", systemImage: "minus") { onChangeCount(item.count - 1) }
        }

        let otherLists = lists.filter { $0.persistentModelID != item.list?.persistentModelID }
        if !otherLists.isEmpty {
            Menu("Move To", systemImage: "arrow.right.square") {
                ForEach(otherLists) { list in
                    Button(list.name) { onMove(list) }
                }
            }
        }

        if let users, users.count > 1 {
            Menu("Packer", systemImage: "person") {
                ForEach(users) { user in
                    Button {
                        onAssign(user)
                    } label: {
                        if user.persistentModelID == item.user?.persistentModelID {
                            Label(user.name, systemImage: "checkmark")
                        } else {
                            Text(user.name)
                        }
                    }
                }
            }
        }

        Divider()

        Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
    }
}

// MARK: - Suitcase Dock

/// Floating progress dock; the suitcase fills from the bottom as items are packed
private struct SuitcaseDock: View {
    let packed: Int
    let total: Int

    private var progress: Double {
        total == 0 ? 0 : Double(packed) / Double(total)
    }

    private var isDone: Bool {
        total > 0 && packed == total
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Image(systemName: "suitcase.rolling.fill")
                    .foregroundStyle(.quaternary)
                Image(systemName: "suitcase.rolling.fill")
                    .foregroundStyle(isDone ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
                    .mask {
                        GeometryReader { proxy in
                            Rectangle()
                                .frame(height: proxy.size.height * progress)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }
            }
            .font(.system(size: 28))
            .symbolEffect(.bounce, value: packed)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(isDone ? "Ready to go!" : "\(total - packed) left to pack")
                    .font(.headline)
                    .contentTransition(.numericText())
                Text("\(packed) of \(total) packed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)

            Text("\(Int((progress * 100).rounded()))%")
                .font(.title2.bold())
                .monospacedDigit()
                .contentTransition(.numericText())
                .accessibilityHidden(true)
        }
        .animation(.snappy, value: packed)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .sensoryFeedback(.success, trigger: isDone) { wasDone, isDone in !wasDone && isDone }
        .accessibilityElement(children: .combine)
    }
}
