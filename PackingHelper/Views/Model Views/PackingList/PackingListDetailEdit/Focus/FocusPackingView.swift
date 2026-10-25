//
//  FocusPackingView.swift
//  PackingHelper
//
//  Trip packing: pack one bag at a time. A rail of section chips (with live progress rings)
//  sits over a horizontal pager with one full page per section. Big tap-anywhere item cards,
//  packed items drop into a "Packed" tray, and finishing a section offers the next one.
//  The add row always targets the page you're on. Hold a chip and drag to reorder sections;
//  the rail's + creates a section or applies a template, as does the "Add a List" page at the
//  end. The rail's first chip, All, opens a page listing every section's items under name
//  headers. Wide layouts show two pages side by side (swipe moves one at a time).
//  A section title's menu turns on Remove Items: minus buttons replace the checkboxes (packed
//  items show as cards too) and the container's toolbar swaps to Undo + Done.
//

import SwiftData
import SwiftUI
import TipKit
import UniformTypeIdentifiers

/// A pager page: everything at once, one section, or the trailing "Add a List" page
private enum FocusPage: Hashable {
    case all
    case list(PersistentIdentifier)
    case addSection

    var listID: PersistentIdentifier? {
        if case .list(let id) = self { return id }
        return nil
    }
}

struct FocusPackingView: View {
    @Environment(\.modelContext) private var modelContext

    let input: FocusPackingInput

    /// Leading visible page (mirrors `pagerPosition`; change it with `setPage` so the pager scrolls)
    @State private var currentPage: FocusPage?
    /// Drives the pager. Unlike `scrollPosition(id:)`, `scrollTo(id:)` scrolls even when the
    /// position already reads that page, which is what re-landing after a resize needs.
    @State private var pagerPosition = ScrollPosition(idType: FocusPage.self)
    /// Pages visible at once: two when there's room (iPad, unfolded Duo without the AI panel)
    @State private var columns = 1
    /// Where narrowing to one column lands: the page from before widening (so open → close on
    /// the first section stays there), or a section chip tapped while wide. Cleared when the user
    /// swipes or jumps elsewhere, which falls back to the right column's page.
    @State private var pageForNarrowing: FocusPage?
    /// Until then, scroll position reports are the pager settling after a resize/reorder, not swipes
    @State private var settlingUntil = Date.distantPast
    @State private var pendingPacks = PendingPackTracker()
    @State private var detailItem: Item?
    /// One packing tip at a time, the first whose rules pass
    @State private var tips = TipGroup(.firstAvailable) {
        ApplyTemplateTip()
        ReorderSectionsTip()
    }

    /// Every page in order: All, each section, Add a Section
    private var pages: [FocusPage] {
        [.all] + input.lists.map { .list($0.persistentModelID) } + [.addSection]
    }

    /// Pages on screen, leading first. All always fills the whole width on its own.
    private var visiblePages: [FocusPage] {
        if currentPage == .all { return [.all] }
        let pages = pages
        guard let currentPage, let index = pages.firstIndex(of: currentPage) else { return [] }
        return Array(pages[index..<min(index + columns, pages.count)])
    }

    /// Sections with their own page on screen; their chips show as selected
    private var visibleListIDs: [PersistentIdentifier] {
        visiblePages.compactMap(\.listID)
    }

    /// Sections whose items are on screen: all of them while the All page is showing
    private var listIDsOnScreen: [PersistentIdentifier] {
        visiblePages.contains(.all) ? input.lists.map(\.persistentModelID) : visibleListIDs
    }

    private var isAllVisible: Bool {
        visiblePages.contains(.all)
    }

    private var isAddPageVisible: Bool {
        visiblePages.contains(.addSection)
    }

    var body: some View {
        VStack(spacing: 0) {
            FocusBagRail(
                input: input,
                visibleListIDs: visibleListIDs,
                isAllVisible: isAllVisible,
                isAddPageVisible: isAddPageVisible,
                currentTip: tips.currentTip,
                onSelectAll: goToAll,
                onSelect: goTo,
                onMove: moveList
            )

            pager
        }
        .onChange(of: input.lists.count, initial: true) { _, sectionCount in
            ApplyTemplateTip.tripHasNoSections = sectionCount == 0
            ReorderSectionsTip.sectionCount = sectionCount
        }
        .onAppear {
            if currentPage == nil {
                let listID = input.add.targetList.wrappedValue?.persistentModelID
                    ?? input.lists.first?.persistentModelID
                let focus = listID.map(FocusPage.list) ?? .addSection
                // Snap (not setPage): the pager may not be laid out yet, and snap retries once it is.
                // Width may already have been measured as wide.
                snap(to: columns > 1 ? leadingPage(focusingOnRight: focus) : focus, afterResize: true)
                if columns > 1 {
                    pageForNarrowing = focus
                }
            }
        }
        .onChange(of: pagerPosition) {
            // While settling, the scroll view can report pages it passes through; the snap decides
            guard Date.now >= settlingUntil,
                  let page = pagerPosition.viewID(type: FocusPage.self),
                  page != currentPage
            else { return }
            // User swipe
            currentPage = page
            pageForNarrowing = nil
        }
        .onChange(of: currentPage) {
            syncTargetToPage()
        }
        .onChange(of: input.add.targetList.wrappedValue?.persistentModelID) { _, id in
            // The accessory bar's section picker (or a trailing page's Add Item) brings that section on screen
            if let id, !listIDsOnScreen.contains(id) {
                withAnimation(.smooth) { setPage(.list(id)) }
            }
        }
        .onChange(of: input.add.isAdding) { _, isAdding in
            // The bottom bar's + from the "Add a List" page: bring the target section back on screen
            if isAdding, let id = input.add.targetList.wrappedValue?.persistentModelID,
               !listIDsOnScreen.contains(id) {
                withAnimation(.smooth) { setPage(.list(id)) }
            }
        }
        .onChange(of: input.lists.map(\.persistentModelID)) { oldIDs, ids in
            // A section was just created or applied from a template: open it
            if let added = ids.first(where: { !oldIDs.contains($0) }) {
                ApplyTemplateTip().invalidate(reason: .actionPerformed)
                withAnimation(.smooth) { setPage(.list(added)) }
                return
            }
            // The page showing was deleted
            if let currentPage, !pages.contains(currentPage) {
                setPage(ids.first.map(FocusPage.list) ?? .addSection)
            }
        }
        .sheet(item: $detailItem) { item in
            ItemDetailSheet(item: item, lists: input.lists, users: input.users)
        }
    }

    private var pager: some View {
        GeometryReader { proxy in
            let pageWidth = proxy.size.width / CGFloat(columns)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    FocusAllItemsPage(
                        input: input,
                        sectionPagesOnScreen: visibleListIDs,
                        pendingPacks: pendingPacks,
                        onShowDetails: { detailItem = $0 }
                    )
                    // Full width even in the two-column layout: one swipe on, the sections pair up
                    .frame(width: proxy.size.width)
                    .id(FocusPage.all)

                    ForEach(input.lists) { list in
                        FocusBagPage(
                            list: list,
                            input: input,
                            pendingPacks: pendingPacks,
                            nextList: nextIncompleteList(after: list),
                            onShowDetails: { detailItem = $0 },
                            onGoTo: goTo
                        )
                        .frame(width: pageWidth)
                        .overlay(alignment: .leading) {
                            if columns > 1 { ColumnSeparator() }
                        }
                        .id(FocusPage.list(list.persistentModelID))
                    }

                    // Always last. In the wide layout it also lets the final section reach the leading column.
                    FocusAddSectionPage(input: input)
                        .frame(width: pageWidth)
                        .overlay(alignment: .leading) {
                            if columns > 1 { ColumnSeparator() }
                        }
                        .id(FocusPage.addSection)
                }
                .scrollTargetLayout()
            }
            // One page per swipe, even when two are showing
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollPosition($pagerPosition)
            .scrollIndicators(.hidden)
        }
        // The scroll view runs under the Duo's side toolbar; pages are sized to the safe area,
        // so clip the next page instead of letting it peek out under the toolbar
        .clipped()
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { _, width in
            // Rotating or unfolding resizes every page but keeps the old scroll offset, which
            // strands the pager between pages. Pick the page to land on with the old column
            // count, then snap to it at the new size.
            let newColumns = width >= 700 ? 2 : 1
            // The first measurement goes through the same rule, so a view that appears already wide
            // still puts the page in focus on the right
            let page = pageToKeep(newColumns: newColumns)
            columns = newColumns
            snap(to: page, afterResize: true)
        }
    }

    /// Moves to `page` on request (chip tap, new section, add target): the user has moved on,
    /// so narrowing no longer returns to the pre-widening page
    private func setPage(_ page: FocusPage?) {
        pageForNarrowing = nil
        currentPage = page
        if let page {
            // `.leading` makes `page` the left column. Without an anchor the scroll only goes far
            // enough to bring the page into view, which in the wide layout leaves it on the right.
            pagerPosition.scrollTo(id: page, anchor: .leading)
        }
    }

    /// The page to lead with after a column change. All never counts; the first section is the
    /// left edge. One → two puts the current page on the right (the first section stays on the
    /// left). Two → one returns to the page from before widening if the user hasn't moved,
    /// otherwise keeps the right page.
    private func pageToKeep(newColumns: Int) -> FocusPage? {
        if columns > 1 && newColumns == 1 {
            if let pageForNarrowing, pages.contains(pageForNarrowing) {
                return pageForNarrowing
            }
            if visiblePages.count > 1 {
                return visiblePages[1]
            }
            return currentPage == .all ? firstSectionPage : currentPage
        }
        if columns == 1 && newColumns > 1, let currentPage {
            pageForNarrowing = currentPage == .all ? firstSectionPage : currentPage
            return leadingPage(focusingOnRight: currentPage)
        }
        return currentPage
    }

    /// The first real section (All doesn't count), or Add a Section when there are none
    private var firstSectionPage: FocusPage {
        input.lists.first.map { .list($0.persistentModelID) } ?? .addSection
    }

    /// Wide layout: the leading page that puts `page` in the right column. Never All: the first
    /// section (or All itself) leads with the first section on the left.
    private func leadingPage(focusingOnRight page: FocusPage) -> FocusPage {
        let pages = pages
        guard let index = pages.firstIndex(of: page), index > 0 else { return firstSectionPage }
        let previous = pages[index - 1]
        // The page before the first section is All: the first section leads instead
        return previous == .all ? page : previous
    }

    /// Re-scrolls to `page` without animation after the pages moved or resized under the scroll view
    private func snap(to page: FocusPage?, afterResize: Bool = false) {
        guard let page else { return }
        currentPage = page
        settlingUntil = .now + (afterResize ? 0.5 : 0.15)

        var transaction = Transaction()
        transaction.disablesAnimations = true
        let scroll = {
            // `ScrollPosition` is a value: if it already reads `page` (but the scroll view never got
            // there, e.g. on first layout it sits at offset 0 showing All), scrolling to `page` again
            // isn't a change and does nothing. Reset it first so the second write always scrolls.
            pagerPosition = ScrollPosition(idType: FocusPage.self)
            DispatchQueue.main.async {
                withTransaction(transaction) { pagerPosition.scrollTo(id: page, anchor: .leading) }
            }
        }
        DispatchQueue.main.async(execute: scroll)
        if afterResize {
            // The scroll view adjusts its own offset as the rotation finishes; land again once it settles
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: scroll)
        }
    }

    private func goTo(_ list: PackingList) {
        // Already has its page on screen (e.g. the trailing column): just make it the add target,
        // and the page to keep if the layout narrows
        if visibleListIDs.contains(list.persistentModelID) {
            setTarget(list)
            if columns > 1 {
                pageForNarrowing = .list(list.persistentModelID)
            }
            return
        }
        withAnimation(.smooth) {
            setPage(.list(list.persistentModelID))
        }
    }

    private func goToAll() {
        guard !isAllVisible else { return }
        withAnimation(.smooth) {
            setPage(.all)
        }
    }

    /// Live reorder while a chip is dragged. `index` is the slot among the other sections.
    private func moveList(_ list: PackingList, to index: Int) {
        guard input.lists.firstIndex(where: { $0.persistentModelID == list.persistentModelID }) != index else {
            return
        }

        let page = currentPage
        var lists = input.lists
        withAnimation(.snappy) {
            SortOrderManager.reorderLists(&lists, moving: list, to: index)
        }
        ReorderSectionsTip().invalidate(reason: .actionPerformed)

        // The pager's pages moved under it; snap back to the page that was showing
        snap(to: page)
    }

    /// New items (and the bottom bar's +) go to a section that's on screen: keep the target while
    /// it's still visible, otherwise follow the first section page showing
    private func syncTargetToPage() {
        if let target = input.add.targetList.wrappedValue?.persistentModelID,
           listIDsOnScreen.contains(target) {
            return
        }
        guard let id = visibleListIDs.first,
              let list = input.lists.first(where: { $0.persistentModelID == id })
        else { return }
        setTarget(list)
    }

    private func setTarget(_ list: PackingList) {
        guard list.persistentModelID != input.add.targetList.wrappedValue?.persistentModelID else { return }
        if input.add.isAdding {
            // Saves anything typed for the previous section, then moves the row here
            input.add.start(list)
        } else {
            input.add.targetList.wrappedValue = list
        }
    }

    /// The next section (wrapping) that still has something to pack
    private func nextIncompleteList(after list: PackingList) -> PackingList? {
        guard let index = input.lists.firstIndex(where: { $0.persistentModelID == list.persistentModelID }) else {
            return nil
        }
        let rest = input.lists[(index + 1)...] + input.lists[..<index]
        return rest.first { list in input.items(in: list).contains { !$0.isPacked } }
    }
}

/// Counts the packing tips' rules depend on
// MARK: - Rail

private struct FocusBagRail: View {
    let input: FocusPackingInput
    /// Sections on screen (two in the wide layout); their chips show as selected
    let visibleListIDs: [PersistentIdentifier]
    /// Highlights the All chip while the All page is showing
    let isAllVisible: Bool
    /// Highlights the + like a selected chip while the "Add a List" page is showing
    let isAddPageVisible: Bool
    /// The packing tip showing, if it anchors to the rail
    let currentTip: (any Tip)?
    let onSelectAll: () -> Void
    let onSelect: (PackingList) -> Void
    /// Moves a section to a slot among the other sections
    let onMove: (PackingList, Int) -> Void

    private static let coordinateSpace = "focusBagRail"
    /// Dragging this close to either edge scrolls the rail
    private static let autoscrollEdge: CGFloat = 44

    /// Section whose chip is being dragged (hold a chip, then drag to reorder)
    @State private var draggingList: PackingList?
    /// Chip frames in the rail's visible bounds, the same space as drop locations
    @State private var chipFrames: [PersistentIdentifier: CGRect] = [:]
    @State private var position = ScrollPosition(idType: PersistentIdentifier.self)
    @State private var scrollGeometry = RailScrollGeometry()

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Button(action: onSelectAll) {
                    FocusBagChip(name: "All", isSelected: isAllVisible)
                }
                .buttonStyle(PressableCardStyle(scale: 0.94))
                .accessibilityLabel("All Items")

                ForEach(input.lists) { list in
                    chip(for: list)
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .named(Self.coordinateSpace))
                        } action: { frame in
                            chipFrames[list.persistentModelID] = frame
                        }
                        .id(list.persistentModelID)
                }

                addSectionMenu
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        .scrollPosition($position)
        .onScrollGeometryChange(for: RailScrollGeometry.self) { geometry in
            RailScrollGeometry(
                offset: geometry.contentOffset.x,
                maxOffset: max(0, geometry.contentSize.width - geometry.containerSize.width),
                width: geometry.containerSize.width
            )
        } action: { _, geometry in
            scrollGeometry = geometry
        }
        .popoverTip(currentTip as? ReorderSectionsTip, arrowEdge: .top)
        .coordinateSpace(.named(Self.coordinateSpace))
        // One drop target for the whole rail, so gaps, the ends, and past the last chip all work
        .onDrop(
            of: [UTType.text],
            delegate: ChipReorderDropDelegate(draggingList: $draggingList, onUpdate: dragMoved(to:))
        )
        .onChange(of: visibleListIDs.first) { _, id in
            guard let id else { return }
            withAnimation(.smooth) { position.scrollTo(id: id, anchor: .center) }
        }
        .onChange(of: isAllVisible) { _, isVisible in
            if isVisible {
                withAnimation(.smooth) { position.scrollTo(edge: .leading) }
            }
        }
        .onChange(of: isAddPageVisible) { _, isVisible in
            if isVisible {
                withAnimation(.smooth) { position.scrollTo(edge: .trailing) }
            }
        }
    }

    private func chip(for list: PackingList) -> some View {
        let items = input.items(in: list)
        let label = FocusBagChip(
            name: list.name,
            packed: items.filter(\.isPacked).count,
            total: items.count,
            isSelected: visibleListIDs.contains(list.persistentModelID)
        )

        // No context menu here: it would open before the drag lifts. Section actions live on the page header.
        return Button {
            onSelect(list)
        } label: {
            label
        }
        .buttonStyle(PressableCardStyle(scale: 0.94))
        .modifier(ChipReorderDrag(list: list, isEnabled: !input.isRemovingItems, draggingList: $draggingList) { label })
        .accessibilityHint(input.isRemovingItems ? "" : "Hold and drag to reorder")
        .accessibilityActions {
            Button("Edit List") { input.onEditList(list) }
            if let index = index(of: list) {
                if index > 0 {
                    Button("Move Left") { onMove(list, index - 1) }
                }
                if index < input.lists.count - 1 {
                    Button("Move Right") { onMove(list, index + 1) }
                }
            }
        }
    }

    private var addSectionMenu: some View {
        Menu {
            Button("Apply Template", systemImage: "doc.on.doc", action: input.onApplyTemplate)
            Button("New List", systemImage: "plus", action: input.onCreateList)
        } label: {
            Image(systemName: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isAddPageVisible ? .white : .primary)
                .frame(width: 38, height: 38)
                .background(isAddPageVisible ? Color.accentColor : Color(.secondarySystemGroupedBackground), in: .circle)
                .contentShape(.circle)
                .animation(.snappy, value: isAddPageVisible)
        }
        .buttonStyle(.plain)
        .popoverTip(currentTip as? ApplyTemplateTip, arrowEdge: .top)
        .disabled(input.isRemovingItems)
        .accessibilityLabel("Add List")
        .accessibilityAddTraits(isAddPageVisible ? .isSelected : [])
    }

    private func index(of list: PackingList) -> Int? {
        input.lists.firstIndex { $0.persistentModelID == list.persistentModelID }
    }

    /// The dragged section's slot is how many of the other chips sit left of the finger
    private func dragMoved(to location: CGPoint) {
        guard let draggingList else { return }
        let others = input.lists.filter { $0.persistentModelID != draggingList.persistentModelID }
        let slot = others.filter { list in
            (chipFrames[list.persistentModelID]?.midX ?? .infinity) < location.x
        }.count
        onMove(draggingList, slot)
        autoscroll(at: location.x)
    }

    private func autoscroll(at x: CGFloat) {
        let step: CGFloat
        if x < Self.autoscrollEdge {
            step = -20
        } else if x > scrollGeometry.width - Self.autoscrollEdge {
            step = 20
        } else {
            return
        }
        let offset = min(max(0, scrollGeometry.offset + step), scrollGeometry.maxOffset)
        guard offset != scrollGeometry.offset else { return }
        withAnimation(.linear(duration: 0.1)) {
            position.scrollTo(x: offset)
        }
    }
}

/// Hold a chip and drag to reorder; off in Remove Items mode
private struct ChipReorderDrag<Preview: View>: ViewModifier {
    let list: PackingList
    let isEnabled: Bool
    @Binding var draggingList: PackingList?
    @ViewBuilder let preview: () -> Preview

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .onDrag {
                    draggingList = list
                    return NSItemProvider(object: list.uuid.uuidString as NSString)
                } preview: {
                    preview()
                }
        } else {
            content
        }
    }
}

private struct RailScrollGeometry: Equatable {
    var offset: CGFloat = 0
    var maxOffset: CGFloat = 0
    var width: CGFloat = 0
}

private struct ChipReorderDropDelegate: DropDelegate {
    @Binding var draggingList: PackingList?
    let onUpdate: (CGPoint) -> Void

    /// Only our own chip drags (not text dragged in from elsewhere)
    func validateDrop(info: DropInfo) -> Bool {
        draggingList != nil
    }

    func dropEntered(info: DropInfo) {
        onUpdate(info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onUpdate(info.location)
        // Move, not copy: no green plus badge on the drag preview
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingList = nil
        return true
    }
}

private struct FocusBagChip: View {
    let name: String
    /// nil for the All chip, which shows no progress
    var packed: Int? = nil
    var total: Int = 0
    let isSelected: Bool

    private var isComplete: Bool { total > 0 && packed == total }

    var body: some View {
        HStack(spacing: 8) {
            if let packed {
                ZStack {
                    PackProgressRing(
                        progress: total == 0 ? 0 : Double(packed) / Double(total),
                        lineWidth: 2.5,
                        tint: isSelected ? .white : .accentColor
                    )
                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .heavy))
                    }
                }
                .frame(width: 18, height: 18)
            }

            Text(name)
                .fontWeight(.semibold)
                .lineLimit(1)

            if let packed, !isComplete && total > 0 {
                Text("\(total - packed)")
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                    .contentTransition(.numericText())
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .frame(height: 38)
        .foregroundStyle(isSelected ? .white : .primary)
        .background(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground), in: .capsule)
        .animation(.snappy, value: packed)
        .animation(.snappy, value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(packed.map { isComplete ? "All packed" : "\(total - $0) left to pack" } ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Vertical hairline between the wide layout's columns (a Divider in an overlay draws horizontally)
private struct ColumnSeparator: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 1 / displayScale)
            .accessibilityHidden(true)
    }
}

// MARK: - Add Section Page

/// The last page: swipe past the final section to add another
private struct FocusAddSectionPage: View {
    let input: FocusPackingInput

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text("Add a List")
                .font(.title2.bold())

            Text("Bring in one of your templates, or start an empty list.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                EmptyStateButton(title: "Apply Template", systemImage: "doc.on.doc", action: input.onApplyTemplate)
                EmptyStateButton(title: "New List", systemImage: "plus", isProminent: false, action: input.onCreateList)
            }
            .padding(.top, 8)
            .disabled(input.isRemovingItems)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Page

private struct FocusBagPage: View {
    let list: PackingList
    let input: FocusPackingInput
    let pendingPacks: PendingPackTracker
    let nextList: PackingList?
    let onShowDetails: (Item) -> Void
    let onGoTo: (PackingList) -> Void

    var body: some View {
        let items = input.items(in: list)
        // Remove Items mode lists packed items as cards too, so they can be removed
        let unpacked = input.isRemovingItems ? items : pendingPacks.visibleUnpacked(items)
        let packed = input.isRemovingItems ? [] : pendingPacks.settledPacked(items)
        let packedCount = items.filter(\.isPacked).count
        let isComplete = !items.isEmpty && packedCount == items.count

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(packed: packedCount, total: items.count, isComplete: isComplete)

                    if isComplete && unpacked.isEmpty {
                        completionCard
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }

                    FocusSectionItems(
                        list: list,
                        unpacked: unpacked,
                        input: input,
                        pendingPacks: pendingPacks,
                        onShowDetails: onShowDetails
                    )

                    if !packed.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Packed · \(packed.count)", systemImage: "suitcase.rolling.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())

                            FocusPackedChips(items: packed, pendingPacks: pendingPacks)
                        }
                    }

                    // Blank space: tap to add here, or to finish adding
                    Color.clear
                        .frame(height: 160)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !input.isRemovingItems { input.add.tapEmpty(list) }
                        }
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .animation(.packingSpring, value: unpacked.map(\.persistentModelID))
                .animation(.packingSpring, value: isComplete)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: input.add.isTarget(list)) { _, isTarget in
                if isTarget { scrollToNewRow(proxy) }
            }
            .onChange(of: items.count) {
                if input.add.isTarget(list) { scrollToNewRow(proxy) }
            }
        }
        .sensoryFeedback(.success, trigger: isComplete) { wasComplete, isComplete in
            !wasComplete && isComplete
        }
    }

    private func scrollToNewRow(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                proxy.scrollTo(NewItemRow.scrollID(for: list), anchor: .bottom)
            }
        }
    }

    private func header(packed: Int, total: Int, isComplete: Bool) -> some View {
        let progress = total == 0 ? 0 : Double(packed) / Double(total)

        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(list.name)
                    .font(.largeTitle.bold())
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)

                Text(statusText(packed: packed, total: total, isComplete: isComplete))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)

            ZStack {
                PackProgressRing(progress: progress, lineWidth: 6)
                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.title2.bold())
                        .foregroundStyle(.tint)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.caption.bold())
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .frame(width: 56, height: 56)
            .accessibilityHidden(true)
        }
        .animation(.snappy, value: packed)
        .contentShape(Rectangle())
        .contextMenu {
            FocusSectionMenu(list: list, input: input)
        }
    }

    private func statusText(packed: Int, total: Int, isComplete: Bool) -> String {
        if total == 0 { return "Nothing in this list yet" }
        if isComplete { return "All \(total) packed" }
        return "\(total - packed) to go · \(packed) of \(total) packed"
    }

    private var completionCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)

            Text("\(list.name) is packed")
                .font(.headline)

            if let nextList {
                Button {
                    onGoTo(nextList)
                } label: {
                    Label("Next: \(nextList.name)", systemImage: "arrow.right")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Text("Everything is packed. Ready to go!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }
}

// MARK: - Shared Page Pieces

/// Section actions in the page header's and the All page headers' context menus
private struct FocusSectionMenu: View {
    let list: PackingList
    let input: FocusPackingInput

    var body: some View {
        if !input.isRemovingItems {
            Button("New Item", systemImage: "plus") { input.add.start(list) }
        }
        Button("Edit List", systemImage: "pencil") { input.onEditList(list) }
        if !input.isRemovingItems {
            Button("Remove Items", systemImage: "minus.circle", action: input.onStartRemovingItems)
        }
        Divider()
        Button("Delete List", systemImage: "trash", role: .destructive) { input.onDeleteList(list) }
    }
}

/// A section's unpacked item cards followed by its add card (inline new item row or dashed button)
private struct FocusSectionItems: View {
    @Environment(\.modelContext) private var modelContext

    let list: PackingList
    let unpacked: [Item]
    let input: FocusPackingInput
    let pendingPacks: PendingPackTracker
    let onShowDetails: (Item) -> Void
    /// Off when another page on screen already shows this section's new item row (one text field only)
    var showsInlineRow = true

    var body: some View {
        VStack(spacing: 6) {
            ForEach(unpacked) { item in
                FocusItemCard(
                    item: item,
                    isRemoving: input.isRemovingItems,
                    showsPacker: input.hasMultiplePackers,
                    otherLists: input.lists.filter { $0.persistentModelID != list.persistentModelID },
                    onToggle: { pendingPacks.toggle(item) },
                    onShowDetails: { onShowDetails(item) },
                    onMove: { target in
                        withAnimation(.packingSpring) { PackingItemActions.moveToList(item, target) }
                    },
                    onDelete: {
                        withAnimation(.packingSpring) { modelContext.delete(item) }
                    },
                    onRemove: { input.onRemoveItem(item) }
                )
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .scale(scale: 0.6, anchor: .bottom).combined(with: .opacity)
                ))
            }

            if !input.isRemovingItems {
                addCard
            }
        }
    }

    /// The inline new item row in this section, otherwise a dashed card that starts one
    @ViewBuilder
    private var addCard: some View {
        if input.add.isTarget(list) && showsInlineRow {
            HStack(spacing: 12) {
                PackCheckbox(isPacked: false, size: 22)
                    .opacity(0.6)
                PersistentTextField(
                    text: input.add.name,
                    isFocused: input.add.isFocused,
                    placeholder: "New Item",
                    onSubmit: input.add.submit
                )
                if input.add.count > 1 {
                    Text("×\(input.add.count)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
            .id(NewItemRow.scrollID(for: list))
        } else {
            Button {
                input.add.start(list)
            } label: {
                Label("Add Item", systemImage: "plus")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                            .foregroundStyle(.tint.opacity(0.4))
                    }
                    .contentShape(.rect(cornerRadius: 12))
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityLabel("Add Item to \(list.name)")
        }
    }
}

/// Packed items as small chips; tap one to unpack it
private struct FocusPackedChips: View {
    let items: [Item]
    let pendingPacks: PendingPackTracker

    var body: some View {
        TileFlowLayout(spacing: 6) {
            ForEach(items) { item in
                Button {
                    pendingPacks.toggle(item)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.caption2.bold())
                        Text(item.name)
                            .lineLimit(1)
                        if item.count > 1 {
                            Text("×\(item.count)")
                                .monospacedDigit()
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemFill), in: .capsule)
                }
                .buttonStyle(PressableCardStyle(scale: 0.92))
                .transition(.scale(scale: 0.4, anchor: .top).combined(with: .opacity))
                .accessibilityLabel("\(item.name), packed")
                .accessibilityHint("Unpacks the item")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - All Items Page

/// The first page: every section in one scrolling list under pinned name headers, no stats
private struct FocusAllItemsPage: View {
    let input: FocusPackingInput
    /// Sections with their own page beside this one (wide layout); they host the new item row
    let sectionPagesOnScreen: [PersistentIdentifier]
    let pendingPacks: PendingPackTracker
    let onShowDetails: (Item) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                    Text("All Items")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)

                    ForEach(input.lists) { list in
                        let items = input.items(in: list)
                        let unpacked = input.isRemovingItems ? items : pendingPacks.visibleUnpacked(items)
                        let packed = input.isRemovingItems ? [] : pendingPacks.settledPacked(items)

                        Section {
                            FocusSectionItems(
                                list: list,
                                unpacked: unpacked,
                                input: input,
                                pendingPacks: pendingPacks,
                                onShowDetails: onShowDetails,
                                showsInlineRow: !sectionPagesOnScreen.contains(list.persistentModelID)
                            )
                            .animation(.packingSpring, value: unpacked.map(\.persistentModelID))

                            if !packed.isEmpty {
                                FocusPackedChips(items: packed, pendingPacks: pendingPacks)
                                    .padding(.top, 4)
                            }
                        } header: {
                            sectionHeader(list)
                        }
                    }

                    // Blank space: tap to add to the current section, or to finish adding
                    Color.clear
                        .frame(height: 160)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !input.isRemovingItems { input.add.tapEmpty(nil) }
                        }
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: input.add.isAdding) { _, isAdding in
                if isAdding { scrollToNewRow(proxy) }
            }
            .onChange(of: input.add.targetList.wrappedValue?.persistentModelID) {
                if input.add.isAdding { scrollToNewRow(proxy) }
            }
            .onChange(of: input.lists.reduce(0) { $0 + ($1.items?.count ?? 0) }) {
                // Return added an item: keep the new row above the keyboard
                if input.add.isAdding { scrollToNewRow(proxy) }
            }
        }
    }

    private func sectionHeader(_ list: PackingList) -> some View {
        Text(list.name)
            .font(.title3.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
            .padding(.bottom, 4)
            // Opaque so rows scroll under the pinned header
            .background(Color(.systemGroupedBackground))
            .contentShape(Rectangle())
            .contextMenu {
                FocusSectionMenu(list: list, input: input)
            }
            .accessibilityAddTraits(.isHeader)
    }

    private func scrollToNewRow(_ proxy: ScrollViewProxy) {
        guard let target = input.add.targetList.wrappedValue else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                proxy.scrollTo(NewItemRow.scrollID(for: target), anchor: .bottom)
            }
        }
    }
}

// MARK: - Item Card

private struct FocusItemCard: View {
    let item: Item
    /// Remove Items mode: a remove button replaces the checkbox and tapping the card does nothing
    let isRemoving: Bool
    let showsPacker: Bool
    let otherLists: [PackingList]
    let onToggle: () -> Void
    let onShowDetails: () -> Void
    let onMove: (PackingList) -> Void
    let onDelete: () -> Void
    let onRemove: () -> Void

    var body: some View {
        if isRemoving {
            removableCard
        } else {
            packableCard
        }
    }

    private var packableCard: some View {
        Button(action: onToggle) {
            cardContent {
                PackCheckbox(isPacked: item.isPacked, size: 22)
            }
        }
        .buttonStyle(PressableCardStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: item.isPacked)
        .contextMenu {
            Button("Details", systemImage: "info.circle", action: onShowDetails)
            if !otherLists.isEmpty {
                Menu("Move To", systemImage: "arrow.right.square") {
                    ForEach(otherLists) { list in
                        Button(list.name) { onMove(list) }
                    }
                }
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(item.isPacked ? "Packed" : "Not packed")
        .accessibilityHint(item.isPacked ? "Unpacks the item" : "Packs the item")
    }

    private var removableCard: some View {
        cardContent {
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
                    // Reach ~44pt without growing the card
                    .contentShape(Rectangle().inset(by: -11))
            }
            .buttonStyle(.plain)
            .transition(.scale.combined(with: .opacity))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(item.isPacked ? "Packed" : "Not packed")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Removes the item")
        .accessibilityAction { onRemove() }
    }

    private var accessibilityName: String {
        item.count > 1 ? "\(item.name), \(item.count)" : item.name
    }

    private func cardContent(@ViewBuilder leading: () -> some View) -> some View {
        HStack(spacing: 12) {
            leading()

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body.weight(.medium))
                    .strikethrough(item.isPacked)
                    .foregroundStyle(item.isPacked ? .secondary : .primary)
                    .multilineTextAlignment(.leading)

                if showsPacker, let user = item.user {
                    Text(user.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(user.userColor)
                }
            }

            Spacer(minLength: 0)

            if item.count > 1 {
                Text("×\(item.count)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        .contentShape(.rect(cornerRadius: 12))
    }
}
