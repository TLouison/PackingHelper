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
        // Nothing to apply without templates: skip the menu and create a list straight away
        if defaultLists.isEmpty {
            Button(action: addNewList) {
                label
            }
        } else {
            Menu {
                Button("New List", systemImage: "plus", action: addNewList)

                Button("Apply Template", systemImage: "doc.on.doc") {
                    withAnimation {
                        isApplyingDefaultPackingList.toggle()
                    }
                }
            } label: {
                label
            }
        }
    }

    private var label: some View {
        EmptyStateButtonLabel(title: "Add List", systemImage: "plus")
    }

    private func addNewList() {
        withAnimation {
            isAddingNewPackingList.toggle()
        }
    }
}

//#Preview {
//    CreateListMenu()
//}
