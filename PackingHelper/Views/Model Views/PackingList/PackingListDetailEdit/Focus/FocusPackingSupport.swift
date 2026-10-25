//
//  FocusPackingSupport.swift
//  PackingHelper
//
//  Shared pieces for FocusPackingView: the container's input, item actions, the
//  Remove Items undo record, and small controls.
//

import SwiftData
import SwiftUI

// MARK: - Start Page

/// Which page trip packing opens on (Settings → Trips)
enum PackingStartPage: String, CaseIterable {
    static let storageKey = "packingStartPage"

    case all = "All Items"
    case firstList = "First List"
}

// MARK: - Input

/// Inline add-item state owned by PackingListContainerView (the accessory bar above the
/// keyboard edits count, packer, and target section)
struct PackingAddFlow {
    let isAdding: Bool
    let targetList: Binding<PackingList?>
    let name: Binding<String>
    let isFocused: Binding<Bool>
    let count: Int
    /// Return key: save and keep the row open
    let submit: () -> Void
    /// Start adding in a section (nil = current target)
    let start: (PackingList?) -> Void
    /// Blank space: finish adding if active, otherwise start in that section
    let tapEmpty: (PackingList?) -> Void

    func isTarget(_ list: PackingList) -> Bool {
        isAdding && targetList.wrappedValue?.persistentModelID == list.persistentModelID
    }
}

struct FocusPackingInput {
    let trip: Trip
    /// Sections in display order
    let lists: [PackingList]
    let users: [User]?
    /// Packer filter from the container's user selector
    let selectedUser: User?
    let add: PackingAddFlow
    let onEditList: (PackingList) -> Void
    let onCreateList: () -> Void
    let onApplyTemplate: () -> Void
    /// Asks for confirmation, then deletes the section
    let onDeleteList: (PackingList) -> Void
    /// Remove Items mode: cards swap their checkbox for a remove button; packing and adding are off
    let isRemovingItems: Bool
    let onStartRemovingItems: () -> Void
    /// Deletes right away; the toolbar's Undo puts it back
    let onRemoveItem: (Item) -> Void

    var hasMultiplePackers: Bool {
        (users?.count ?? 0) > 1
    }

    /// A section's items in manual order, narrowed to the selected packer
    func items(in list: PackingList) -> [Item] {
        var items = list.items ?? []
        if let selectedUser {
            items = items.filter { $0.user?.persistentModelID == selectedUser.persistentModelID }
        }
        return Item.sorted(items, sortOrder: .byCustomOrder)
    }
}

// MARK: - Item Actions

@MainActor
enum PackingItemActions {
    /// Moves an item to the end of another section
    static func moveToList(_ item: Item, _ list: PackingList) {
        guard item.list?.persistentModelID != list.persistentModelID else { return }
        let order = SortOrderManager.nextSortOrder(for: list)
        item.list?.removeItem(item)
        list.addItem(item)
        item.list = list
        item.sortOrder = order
    }
}

// MARK: - Removed Items

/// Enough of a deleted item to put it back where it was (Remove Items mode's Undo)
struct RemovedItem {
    let uuid: UUID
    let name: String
    let category: String
    let count: Int
    let isPacked: Bool
    let created: Date
    let sortOrder: Int
    let user: User?
    let list: PackingList

    init?(_ item: Item) {
        guard let list = item.list else { return nil }
        uuid = item.uuid
        name = item.name
        category = item.category
        count = item.count
        isPacked = item.isPacked
        created = item.created
        sortOrder = item.sortOrder
        user = item.user
        self.list = list
    }

    /// Recreates the item in its section. Deleting doesn't renumber the others, so the old
    /// sort order puts it back in its old spot.
    @MainActor
    func restore(in modelContext: ModelContext) {
        let item = Item(name: name, category: category, count: count, isPacked: isPacked, sortOrder: sortOrder)
        item.uuid = uuid
        item.created = created
        item.user = user?.isDeleted == false ? user : nil
        modelContext.insert(item)
        list.addItem(item)
    }
}

// MARK: - Checkbox

/// Reminders-style check: an empty ring, or a tinted ring around a filled dot
struct PackCheckbox: View {
    let isPacked: Bool
    var size: CGFloat = 22
    var tint: Color = .accentColor

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isPacked ? tint : Color.secondary.opacity(0.5), lineWidth: 1.5)
            Circle()
                .fill(tint)
                .padding(size * 0.18)
                .scaleEffect(isPacked ? 1 : 0.1)
                .opacity(isPacked ? 1 : 0)
        }
        .frame(width: size, height: size)
        .animation(.snappy(duration: 0.2), value: isPacked)
        .accessibilityHidden(true)
    }
}

/// Small determinate ring used for per-section progress
struct PackProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 3
    var tint: Color = .accentColor

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.packingSpring, value: progress)
        .accessibilityHidden(true)
    }
}

extension Collection where Element == Item {
    var packedFraction: Double {
        isEmpty ? 0 : Double(filter(\.isPacked).count) / Double(count)
    }
}

// MARK: - Item Details

/// Full item editor: name, count, packer, section, packed, delete
struct ItemDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let item: Item
    let lists: [PackingList]
    let users: [User]?

    @State private var name: String
    @State private var count: Int
    @State private var user: User?
    @State private var list: PackingList?
    @State private var isPacked: Bool

    init(item: Item, lists: [PackingList], users: [User]?) {
        self.item = item
        self.lists = lists
        self.users = users
        _name = State(initialValue: item.name)
        _count = State(initialValue: item.count)
        _user = State(initialValue: item.user)
        _list = State(initialValue: item.list)
        _isPacked = State(initialValue: item.isPacked)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Item", text: $name)
                    Stepper("Count: \(count)", value: $count, in: 1...99)
                    Toggle("Packed", isOn: $isPacked)
                }

                Section {
                    if lists.count > 1 {
                        Picker("List", selection: $list) {
                            ForEach(lists) { list in
                                Text(list.name).tag(Optional(list))
                            }
                        }
                    }
                    if let users, users.count > 1 {
                        Picker("Packer", selection: $user) {
                            Text("None").tag(User?.none)
                            ForEach(users) { user in
                                Text(user.name).tag(Optional(user))
                            }
                        }
                    }
                }

                Section {
                    Button("Delete Item", role: .destructive) {
                        dismiss()
                        withAnimation(.packingSpring) { modelContext.delete(item) }
                    }
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        withAnimation(.packingSpring) {
            item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            item.count = count
            item.user = user
            item.isPacked = isPacked
            if let list {
                PackingItemActions.moveToList(item, list)
            }
        }
        dismiss()
    }
}

// MARK: - Press Style

/// Shrinks slightly while pressed so taps feel physical
struct PressableCardStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Tile Flow Layout

/// Wrapping layout that caps each subview at the available width (long names wrap instead of overflowing)
struct TileFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = frames(for: subviews, maxWidth: proposal.width ?? .infinity)
        let width = proposal.width ?? frames.map(\.maxX).max() ?? 0
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = frames(for: subviews, maxWidth: bounds.width)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func frames(for subviews: Subviews, maxWidth: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let size = ideal.width > maxWidth
                ? subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
                : ideal
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}
