//
//  DefaultPackingListView.swift
//  PackingHelper
//
//  Created by Todd Louison on 10/20/23.
//

import SwiftUI
import SwiftData
import TipKit

struct DefaultPackingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @Query(
        filter: #Predicate<PackingList> { $0.template == true },
        sort: [SortDescriptor(\.name)],
        animation: .snappy
    )
    private var defaultPackingLists: [PackingList]
    
    private static var now: Date { Date.now }
    @Query(filter: #Predicate<Trip> { $0.endDate <= now }) private var completedTrips: [Trip]
    
    @State private var searchText = ""
    @State private var showingAddSheet = false
    /// Shared by both layouts so the open template survives a compact ↔ regular switch
    /// (e.g. folding/unfolding the Duo): sidebar selection when wide, pushed list when compact.
    @State private var selectedList: PackingList?
    @State private var showingReviewSheet = false
    /// Opened whenever no template is selected, so portrait iPad isn't left with an empty detail column.
    /// Starts `.automatic` (what portrait actually shows) so the first visit animates it open too.
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    
    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasActiveFilters: Bool { !searchQuery.isEmpty }

    /// Templates matching the search by name or by any item, each once: name matches first
    private var searchResults: [TemplateSearchResult] {
        guard hasActiveFilters else { return [] }
        let results = defaultPackingLists.compactMap { TemplateSearchResult(list: $0, query: searchQuery) }
        return results.filter(\.nameMatches) + results.filter { !$0.nameMatches }
    }

    private var filteredLists: [PackingList] {
        hasActiveFilters ? searchResults.map(\.list) : defaultPackingLists
    }
    
    /// Past trips with items that could be saved back to their templates
    private var reviewCount: Int {
        completedTrips.count(where: \.showsTemplateReviewCard)
    }
    
    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                splitView
            } else {
                stackView
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            PackingListEditView(
                isTemplate: true,
                onListCreated: { newList in
                    // Open the new template right away (pushed, or in the detail column when wide)
                    selectedList = newList
                },
                isDeleted: .constant(false),
                fitsContent: true
            )
        }
        .sheet(isPresented: $showingReviewSheet) {
            TemplateReviewTripsSheet()
        }
        .onChange(of: defaultPackingLists.map(\.persistentModelID)) { _, ids in
            // The selected template was deleted (from its settings sheet or elsewhere)
            if let selectedList, !ids.contains(selectedList.persistentModelID) {
                self.selectedList = nil
            }
        }
    }
    
    // MARK: - Compact
    
    private var stackView: some View {
        NavigationStack {
            Group {
                if filteredLists.isEmpty {
                    emptyState
                        .frame(maxHeight: .infinity)
                } else {
                    // The scroll view sits directly under the nav bar so the large title collapses with it
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            if hasActiveFilters {
                                ForEach(searchResults) { result in
                                    TemplateSearchResultCard(result: result, query: searchQuery) {
                                        selectedList = result.list
                                    }
                                }
                            } else {
                                ForEach(filteredLists) { list in
                                    PackingListCard(list: list) {
                                        selectedList = list
                                    }
                                }
                            }
                        }
                        // Both modes key cards by template, so give each mode its own stack; otherwise
                        // the lazy stack can keep showing a plain card where a search result belongs
                        .id(hasActiveFilters)
                        .padding(.horizontal)
                        .padding(.top)
                    }
                }
            }
            // System search under the title; Cancel clears it and returns to the full list
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search templates and items"
            )
            .safeAreaInset(edge: .bottom) { reviewBanner }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Template Lists")
            // Large title level with the + button, matching the Trips tab
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar { listToolbar }
            .navigationDestination(item: $selectedList) { list in
                PackingListContainerView(packingList: list)
            }
        }
    }
    
    // MARK: - Regular
    
    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(filteredLists, selection: $selectedList) { list in
                TemplateSidebarRow(
                    list: list,
                    match: searchResults.first { $0.id == list.persistentModelID },
                    query: searchQuery
                )
                .tag(list)
            }
            .overlay {
                if filteredLists.isEmpty && hasActiveFilters {
                    ContentUnavailableView.search(text: searchQuery)
                }
            }
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search templates and items")
            .safeAreaInset(edge: .bottom) { reviewBanner }
            .navigationTitle("Template Lists")
            .toolbar { listToolbar }
        } detail: {
            NavigationStack {
                if let selectedList {
                    PackingListContainerView(packingList: selectedList)
                        // Fresh container per template so add/edit state doesn't leak between lists
                        .id(selectedList.persistentModelID)
                } else if defaultPackingLists.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemGroupedBackground))
                } else {
                    ContentUnavailableView(
                        "No Template Selected",
                        systemImage: suitcaseIcon,
                        description: Text("Choose a template from the list to view and edit its items.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        // Nothing open in the detail column: show the sidebar so there's something to pick (and the review banner)
        .onAppear {
            guard selectedList == nil, columnVisibility != .all else { return }
            // Deferred a run loop so the slide-in animates instead of landing with the tab switch
            Task { @MainActor in
                withAnimation {
                    columnVisibility = .all
                }
            }
        }
        .onChange(of: selectedList) { _, newValue in
            if newValue == nil {
                withAnimation {
                    columnVisibility = .all
                }
            }
        }
    }
    
    // MARK: - Shared
    
    /// Pinned below the template list so it stays put while the list scrolls
    @ViewBuilder
    private var reviewBanner: some View {
        let reviewCount = self.reviewCount
        if reviewCount > 0 {
            Button {
                SaveToTemplateTip().invalidate(reason: .actionPerformed)
                showingReviewSheet = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Items to Review")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("^[\(reviewCount) past trip](inflect: true) with new items or lists to save")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer(minLength: 0)
                    
                    UnreadBadge(count: reviewCount)
                    
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                // Box inside the label so its padding is part of the tap target
                .roundedBox(background: .ultraThick)
                .shaded()
            }
            .buttonStyle(.plain)
            .popoverTip(SaveToTemplateTip(), arrowEdge: .bottom)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    @ViewBuilder
    private var emptyState: some View {
        if hasActiveFilters {
            PackingListEmptyStateView(
                hasFilters: true,
                message: "Try a different search term",
                actionButtonTitle: "Clear Search",
                onAction: { searchText = "" }
            )
        } else {
            // No templates yet: teach what they're for here, where they're made.
            // Pinned to the top (not centered like ContentUnavailableView) so the button sits mid-screen.
            ScrollView {
                VStack(spacing: 24) {
                    TemplateAnimationView()

                    VStack(spacing: 8) {
                        Text("No Templates Yet")
                            .font(.title2.bold())
                        Text("Save the lists you pack every trip, then apply them to fill a new trip in seconds.")
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)

                    EmptyStateButton(title: "Create Template", systemImage: "plus") {
                        showingAddSheet.toggle()
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 16)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
    
    @ToolbarContentBuilder
    private var listToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showingAddSheet.toggle() } label: {
                Image(systemName: "plus").fontWeight(.semibold)
            }
            .accessibilityLabel("Create Template")
        }
    }
}

private struct TemplateSidebarRow: View {
    let list: PackingList
    var match: TemplateSearchResult? = nil
    var query: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(match == nil ? AttributedString(list.name) : TemplateSearchResult.highlighted(list.name, query: query))
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                Text("\(list.totalItems)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if let match, !match.items.isEmpty {
                ForEach(Array(match.items.prefix(TemplateSearchResult.itemLimit))) { item in
                    Text(TemplateSearchResult.highlighted(item.name, query: query))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if match.items.count > TemplateSearchResult.itemLimit {
                    Text("+\(match.items.count - TemplateSearchResult.itemLimit) more")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// A template that matches the search: by name, by items, or both (it shows once either way)
struct TemplateSearchResult: Identifiable {
    /// Matching items shown under a result before "+N more"
    static let itemLimit = 3

    let list: PackingList
    let nameMatches: Bool
    /// Items whose name matches, in list order
    let items: [Item]

    var id: PersistentIdentifier { list.persistentModelID }

    /// nil when neither the name nor any item matches
    init?(list: PackingList, query: String) {
        let nameMatches = Self.matches(list.name, query: query)
        let items = Item.sorted(list.items ?? [], sortOrder: .byCustomOrder)
            .filter { Self.matches($0.name, query: query) }
        guard nameMatches || !items.isEmpty else { return nil }
        self.list = list
        self.nameMatches = nameMatches
        self.items = items
    }

    private static func matches(_ text: String, query: String) -> Bool {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// `text` with every occurrence of `query` highlighted
    static func highlighted(_ text: String, query: String) -> AttributedString {
        var result = AttributedString()
        var searchStart = text.startIndex
        while !query.isEmpty,
              let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: searchStart..<text.endIndex) {
            result += AttributedString(String(text[searchStart..<range.lowerBound]))
            var match = AttributedString(String(text[range]))
            match.backgroundColor = Color.accentColor.opacity(0.3)
            result += match
            searchStart = range.upperBound
        }
        result += AttributedString(String(text[searchStart...]))
        return result
    }
}

struct FilterChip: View {
    let isSelected: Bool
    let label: String
    let icon: Image
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                icon
                    .foregroundStyle(isSelected ? .white : .accentColor)
                
                Text(label)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? .white : .primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 8))
        }
    }
}

/// A search result: the template's name (match highlighted) and count, with matching items underneath
private struct TemplateSearchResultCard: View {
    let result: TemplateSearchResult
    let query: String
    let onSelect: () -> Void

    private var list: PackingList { result.list }

    var body: some View {
        Button(action: onSelect) {
            content(result)
        }
    }

    private func content(_ match: TemplateSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(TemplateSearchResult.highlighted(list.name, query: query))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(subtitle(match))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal)

            ForEach(Array(match.items.prefix(TemplateSearchResult.itemLimit))) { item in
                Divider().padding(.leading)
                HStack(spacing: 10) {
                    Text("–")
                        .foregroundStyle(.secondary)
                    Text(TemplateSearchResult.highlighted(item.name, query: query))
                        .lineLimit(1)
                    Spacer()
                    if item.count > 1 {
                        Text("×\(item.count)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
                .padding(.vertical, 8)
                .padding(.horizontal)
            }

            if match.items.count > TemplateSearchResult.itemLimit {
                Divider().padding(.leading)
                Text("+\(match.items.count - TemplateSearchResult.itemLimit) more")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .padding(.vertical, 8)
                    .padding(.horizontal)
            }
        }
        .foregroundStyle(.primary)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 12))
    }

    private func subtitle(_ match: TemplateSearchResult) -> String {
        let matching = match.items.count
        if match.nameMatches {
            let total = "\(list.totalItems) \(list.totalItems == 1 ? "item" : "items")"
            return matching > 0 ? "\(total) · \(matching) matching" : total
        }
        return matching == 1 ? "1 matching item" : "\(matching) matching items"
    }
}

struct PackingListCard: View {
    let list: PackingList
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            Text(list.name)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
            
            Spacer()
            
            HStack(spacing: 4) {
                Text("\(list.totalItems)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    
                Image(systemName: "list.bullet")
                    .foregroundStyle(Color.accentColor)
                    .font(.subheadline)
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 12))
    }
}
