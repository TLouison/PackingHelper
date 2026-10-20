//
//  UserListView.swift
//  PackingHelper
//
//  Created by Todd Louison on 6/16/24.
//

import SwiftUI
import SwiftData

struct UserListView: View {
//    @Environment(PurchaseManager.self) private var purchaseManager: PurchaseManager
    
    @Query(sort: \User.created, order: .forward, animation: .smooth) private var users: [User]
    
    @State private var isShowingAddUserSheet = false
    @State private var isShowingSubscriptionStoreSheet = false
    
    var reachedMaxFreeUsers: Bool {
        // Allow user to create 1 user if Plus is not unlocked, infinite if they do.
        return users.count > 0
    }

    var body: some View {
        NavigationStack {
            Group {
                if users.isEmpty {
                    MissingUsersView()
                } else {
                    ZStack {
                        List {
                            ForEach(users, id: \.id) { user in
                                UserListRowView(user: user)
                            }
                        }
                        
//                        if !purchaseManager.hasUnlockedPlus {
//                            VStack {
//                                Spacer()
//                                PackingHelperPlusCTA(headerText: "Add unlimited packers with")
//                                    .padding(.bottom)
//                            }
//                        }
                    }
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
                    .presentationDetents([.height(400)])
            }
            .sheet(isPresented: $isShowingSubscriptionStoreSheet) {
                PlusPaywallView()
            }
        }
    }
}

@available(iOS 18, *)
#Preview(traits: .sampleData) {
    UserListView()
}
