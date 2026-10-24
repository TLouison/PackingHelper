//
//  PackingListSupportViews.swift
//  PackingHelper
//
//  Helper views shared between FocusPackingView and the single-list
//  rendering path inside PackingListContainerView.
//
//  Created by Todd Louison on 9/16/25.
//

import SwiftUI
import SwiftData

// MARK: - User Selector

struct UserSelector: View {
    let users: [User]
    @Binding var selectedUser: User?
    
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(users.sorted { $0.name < $1.name }) { user in
                    Button {
                        if selectedUser != user {
                            DispatchQueue.main.async {
                                withAnimation {
                                    self.selectedUser = user
                                }
                            }
                        } else {
                            withAnimation {
                                self.selectedUser = nil
                            }
                        }
                    } label: {
                        user.pillIcon
                            .scaleEffect(user == selectedUser ? 1.3 : 1.0)
                            .opacity(user == selectedUser || selectedUser == nil ? 1.0 : 0.3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(user.name)
                    .accessibilityAddTraits(user == selectedUser ? .isSelected : [])
                    .accessibilityHint(user == selectedUser ? "Shows every packer's items" : "Shows only \(user.name)'s items")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

// MARK: - Pending Pack Tracker

/// Reminders-style check-off: a newly packed item stays in place briefly
/// (so a second tap can undo it) before moving to the packed section.
@MainActor
@Observable
final class PendingPackTracker {
    private(set) var pendingIDs: Set<PersistentIdentifier> = []
    @ObservationIgnored private var tokens: [PersistentIdentifier: UUID] = [:]

    private let delay: Duration = .seconds(1.5)

    func isPending(_ item: Item) -> Bool {
        pendingIDs.contains(item.persistentModelID)
    }

    /// Items that should render in the unpacked area: unpacked plus recently packed
    func visibleUnpacked(_ items: [Item]) -> [Item] {
        items.filter { !$0.isPacked || isPending($0) }
    }

    /// Items that should render in the packed area: packed and no longer pending
    func settledPacked(_ items: [Item]) -> [Item] {
        items.filter { $0.isPacked && !isPending($0) }
    }

    func toggle(_ item: Item) {
        let id = item.persistentModelID

        guard !item.isPacked else {
            // Unpacking (including undoing a pending pack) is immediate
            tokens[id] = nil
            withAnimation(.packingSpring) {
                pendingIDs.remove(id)
                item.isPacked = false
            }
            return
        }

        withAnimation(.snappy) {
            pendingIDs.insert(id)
            item.isPacked = true
        }

        let token = UUID()
        tokens[id] = token
        Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard let self, self.tokens[id] == token else { return }
            self.tokens[id] = nil
            withAnimation(.packingSpring) {
                _ = self.pendingIDs.remove(id)
            }
        }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox")
                .font(.system(size: 60))
                .foregroundStyle(.gray.opacity(0.3))
            
            Text("You haven't added any items yet!")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("Tap the + button to add your first item")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
