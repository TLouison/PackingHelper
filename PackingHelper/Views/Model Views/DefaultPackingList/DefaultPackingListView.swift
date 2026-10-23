//
//  DefaultPackingListView.swift
//  PackingHelper
//
//  Created by Todd Louison on 10/20/23.
//

import SwiftUI
import SwiftData

struct DefaultPackingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @Query(
        filter: #Predicate<PackingList> { $0.template == true },
        sort: [SortDescriptor(\.name)],
        animation: .snappy
    )
    private var defaultPackingLists: [PackingList]
    
    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var showingSearch = false
    /// Shared by both layouts so the open template survives a compact ↔ regular switch
    /// (e.g. folding/unfolding the Duo): sidebar selection when wide, pushed list when compact.
    @State private var selectedList: PackingList?
    
    private var filteredLists: [PackingList] {
        guard !searchText.isEmpty else { return defaultPackingLists }
        return defaultPackingLists.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    private var hasActiveFilters: Bool { !searchText.isEmpty }
    
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
                    // Wide layout: open the new template in the detail column right away
                    if horizontalSizeClass == .regular {
                        selectedList = newList
                    }
                },
                isDeleted: .constant(false)
            )
            .presentationDetents([.height(200)])
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
        NavigationSplitView {
            VStack(spacing: 0) {
                if showingSearch {
                    searchBar
                }
                
                List(filteredLists, selection: $selectedList) { list in
                    TemplateSidebarRow(list: list)
                        .tag(list)
                }
                .overlay {
                    if filteredLists.isEmpty && hasActiveFilters {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
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
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
    
    // MARK: - Shared
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search templates...", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    private var emptyState: some View {
        PackingListEmptyStateView(
            hasFilters: hasActiveFilters,
            message: hasActiveFilters ?
                "Try a different search term" :
                "Create your first template to get started",
            actionButtonTitle: hasActiveFilters ?
                "Clear Search" : "Create Template",
            onAction: hasActiveFilters ?
                { searchText = "" } : { showingAddSheet.toggle() }
        )
    }
    
    @ToolbarContentBuilder
    private var listToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 16) {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        showingSearch.toggle()
                        if !showingSearch { searchText = "" }
                    }
                } label: {
                    Image(systemName: "magnifyingglass\(hasActiveFilters ? ".circle.fill" : "")")
                        .fontWeight(.semibold)
                        .foregroundStyle(hasActiveFilters ? .accent : .primary)
                }
                
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
