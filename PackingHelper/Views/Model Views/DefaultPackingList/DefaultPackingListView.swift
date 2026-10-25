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
    @State private var showingSearch = false
    @FocusState private var isSearchFocused: Bool
    /// Shared by both layouts so the open template survives a compact ↔ regular switch
    /// (e.g. folding/unfolding the Duo): sidebar selection when wide, pushed list when compact.
    @State private var selectedList: PackingList?
    @State private var showingReviewSheet = false
    /// Opened whenever no template is selected, so portrait iPad isn't left with an empty detail column.
    /// Starts `.automatic` (what portrait actually shows) so the first visit animates it open too.
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    
    private var filteredLists: [PackingList] {
        guard !searchText.isEmpty else { return defaultPackingLists }
        return defaultPackingLists.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    private var hasActiveFilters: Bool { !searchText.isEmpty }
    
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
                isDeleted: .constant(false)
            )
            .presentationDetents([.height(200)])
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
            VStack(spacing: 0) {
                if showingSearch {
                    searchBar
                }
                
                Group {
                    if filteredLists.isEmpty {
                        emptyState
                            .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(filteredLists) { list in
                                    PackingListCard(list: list) {
                                        selectedList = list
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top)
                        }
                    }
                }
                // Tapping anywhere below the search bar ends searching
                .simultaneousGesture(TapGesture().onEnded { isSearchFocused = false })
            }
            .safeAreaInset(edge: .bottom) { reviewBanner }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Template Lists")
            .toolbar { listToolbar }
            .navigationDestination(item: $selectedList) { list in
                PackingListContainerView(packingList: list)
            }
        }
    }
    
    // MARK: - Regular
    
    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                if showingSearch {
                    searchBar
                }
                
                List(filteredLists, selection: $selectedList) { list in
                    TemplateSidebarRow(list: list)
                        .tag(list)
                }
                .simultaneousGesture(TapGesture().onEnded { isSearchFocused = false })
                .overlay {
                    if filteredLists.isEmpty && hasActiveFilters {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
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
                        Text("^[\(reviewCount) past trip](inflect: true) with items to save to templates")
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
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search templates...", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear { isSearchFocused = true }
        .onChange(of: isSearchFocused) { _, isFocused in
            // Tapping away from an empty search closes it; a typed search stays as a filter
            if !isFocused && searchText.isEmpty {
                setSearchShowing(false)
            }
        }
    }

    private func setSearchShowing(_ isShowing: Bool) {
        withAnimation(.spring(response: 0.3)) {
            showingSearch = isShowing
            if !isShowing { searchText = "" }
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
            HStack(spacing: 16) {
                Button {
                    setSearchShowing(!showingSearch)
                } label: {
                    Image(systemName: "magnifyingglass\(hasActiveFilters ? ".circle.fill" : "")")
                        .fontWeight(.semibold)
                        .foregroundStyle(showingSearch ? .accent : .primary)
                }
                .accessibilityLabel(showingSearch ? "Close Search" : "Search Templates")
                
                Button { showingAddSheet.toggle() } label: {
                    Image(systemName: "plus").fontWeight(.semibold)
                }
            }
        }
    }
}

private struct TemplateSidebarRow: View {
    let list: PackingList
    
    var body: some View {
        HStack(spacing: 12) {
            Text(list.name)
                .fontWeight(.medium)
                .lineLimit(1)
            
            Spacer()
            
            Text("\(list.totalItems)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
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

struct PackingListCard: View {
    let list: PackingList
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
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
}
