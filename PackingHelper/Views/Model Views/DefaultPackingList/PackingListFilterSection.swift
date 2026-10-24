//
//  DefaultPackingListFilterView.swift
//  PackingHelper
//
//  Created by Todd Louison on 1/28/25.
//

import SwiftUI

// MARK: - Shared Components

struct PackingListFilterSection: View {
    @Binding var searchText: String
    @Binding var selectedListType: ListType?
    @Binding var selectedUser: User?
    let users: [User]
    let showUserFilter: Bool
    var showTypeFilter: Bool = true
    let hasActiveFilters: Bool

    var onClearFilters: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            searchBar

            if showUserFilter {
                userFilterSection
            }

            if showTypeFilter {
                listTypeFilterSection
            }
            
            if hasActiveFilters {
                Button {
                    onClearFilters()
                } label: {
                    Text("Clear All Filters")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("Search lists...", text: $searchText)
                .textFieldStyle(.plain)
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 12))
    }
    
    private var userFilterSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Filter by User")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(users) { user in
                        FilterChip(
                            isSelected: selectedUser == user,
                            label: user.name,
                            icon: Image(systemName: "person.circle"),
                            action: {
                                withAnimation {
                                    selectedUser = selectedUser == user ? nil : user
                                }
                            }
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
    
    private var listTypeFilterSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Filter by Type")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(ListType.allCases, id: \.self) { type in
                        FilterChip(
                            isSelected: selectedListType == type,
                            label: type.rawValue,
                            icon: Image(systemName: type.icon),
                            action: {
                                withAnimation {
                                    selectedListType = selectedListType == type ? nil : type
                                }
                            }
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct PackingListEmptyStateView: View {
    let hasFilters: Bool
    let message: String
    let actionButtonTitle: String
    let onAction: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "suitcase")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            
            Text("No Lists Found")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: onAction) {
                Text(actionButtonTitle)
                    .fontWeight(.semibold)
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
        }
        .padding(32)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 16))
        .padding(.horizontal)
    }
}

