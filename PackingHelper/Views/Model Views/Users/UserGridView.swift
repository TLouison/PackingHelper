//
//  UserGridView.swift
//  PackingHelper
//
//  Created by Todd Louison on 1/1/25.
//

import SwiftUI
import SwiftData

struct UserGridView: View {
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \User.created, order: .forward, animation: .smooth) private var users: [User]
    
    @State private var selectedUser: User?
    @State private var isShowingAddUserSheet = false
    @State private var isShowingSubscriptionStoreSheet = false
    
    var reachedMaxFreeUsers: Bool {
        return users.count > 0
    }
    
    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if users.isEmpty {
                    MissingUsersView()
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(users) { user in
                            UserGridCell(user: user)
                                .onTapGesture {
                                    selectedUser = user
                                }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Packers")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    SubscriptionAwareButton(localLimitMet: reachedMaxFreeUsers) {
                        isShowingAddUserSheet.toggle()
                    } label: {
                        Label("Add Packer", systemImage: "plus.circle")
                            .symbolEffect(.bounce.down, value: isShowingAddUserSheet)
                    }
                }
            }
            .sheet(isPresented: $isShowingAddUserSheet) {
                UserEditView(user: nil, isPresentedModally: true)
            }
            .sheet(item: $selectedUser) { user in
                UserEditView(user: user, isPresentedModally: true)
            }
            .sheet(isPresented: $isShowingSubscriptionStoreSheet) {
                PlusPaywallView()
            }
        }
    }
}

struct UserGridCell: View {
    let user: User
    
    var templateListCount: Int {
        user.lists?.filter { $0.template == true }.count ?? 0
    }
    
    var body: some View {
        VStack {
            user.profileView
                .frame(width: 80, height: 80)
                .shadow(radius: 2)
            
            Text(user.name)
                .font(.headline)
                .foregroundStyle(user.userColor)
                .lineLimit(1)
            
            Text(pluralizeString("\(templateListCount) template list", count: templateListCount))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 2)
    }
}
