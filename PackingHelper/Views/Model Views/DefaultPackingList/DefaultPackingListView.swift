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
    
    @Query(
        filter: #Predicate<PackingList> { $0.template == true },
        sort: [SortDescriptor(\.name)],
        animation: .snappy
    )
    private var defaultPackingLists: [PackingList]
    
    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var showingSearch = false
    
    private var filteredLists: [PackingList] {
        guard !searchText.isEmpty else { return defaultPackingLists }
        return defaultPackingLists.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    private var hasActiveFilters: Bool { !searchText.isEmpty }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showingSearch {
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
                
                if filteredLists.isEmpty {
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
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredLists) { list in
                                PackingListCard(list: list)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Template Lists")
            .toolbar {
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
            .sheet(isPresented: $showingAddSheet) {
                PackingListEditView(isTemplate: true, isDeleted: .constant(false))
                    .presentationDetents([.height(200)])
            }
        }
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

    var body: some View {
        NavigationLink(destination: PackingListContainerView(packingList: list)) {
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
