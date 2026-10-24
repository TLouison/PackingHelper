//
//  CreateListMenu.swift
//  PackingHelper
//
//  Created by Todd Louison on 6/30/24.
//

import SwiftUI
import SwiftData

struct CreateListMenu: View {
    @Binding var isAddingNewPackingList: Bool
    @Binding var isApplyingDefaultPackingList: Bool

    @Query(
        filter: #Predicate<PackingList>{ $0.template == true}
    ) private var defaultLists: [PackingList]

    var body: some View {
        Menu {
            // Create list options
            Button("New Section", systemImage: "plus") {
                withAnimation {
                    isAddingNewPackingList.toggle()
                }
            }

            if !defaultLists.isEmpty {
                Button("Apply Template", systemImage: "doc.on.doc") {
                    withAnimation {
                        isApplyingDefaultPackingList.toggle()
                    }
                }
            }
        } label: {
            EmptyStateButtonLabel(title: "Add Section", systemImage: "plus")
        }
    }
}

//#Preview {
//    CreateListMenu()
//}
