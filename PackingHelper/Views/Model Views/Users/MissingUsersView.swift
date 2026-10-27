//
//  MissingUsersView.swift
//  PackingHelper
//
//  Created by Todd Louison on 7/13/24.
//

import SwiftUI

struct MissingUsersView: View {
    @State private var showAddPackerSheet = false
    
    var body: some View {
        ContentUnavailableView {
            Label("No Packers Yet", systemImage: "person.fill")
        } description: {
            Text("Add a packer to start planning trips.")
        } actions: {
            EmptyStateButton(title: "Add Packer", systemImage: "person.badge.plus") {
                showAddPackerSheet.toggle()
            }
        }
        .sheet(isPresented: $showAddPackerSheet) {
            UserEditView(user: nil, isPresentedModally: true)
        }
    }
}

#Preview(traits: .sampleData) {
    MissingUsersView()
}
