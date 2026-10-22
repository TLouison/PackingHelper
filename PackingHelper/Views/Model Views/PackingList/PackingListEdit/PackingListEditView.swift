//
//  PackingListCreateView.swift
//  PackingHelper
//
//  Created by Todd Louison on 11/9/23.
//

import SwiftUI
import SwiftData

struct PackingListEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var packingList: PackingList?
    var isTemplate: Bool = false

    var trip: Trip? = nil
    var onListCreated: ((PackingList) -> Void)? = nil

    @Query(sort: \User.created) private var users: [User]

    @State private var listName = ""
    @State private var owner: User?

    @State private var isDeleting: Bool = false
    @Binding var isDeleted: Bool
    
    var formIsValid: Bool {
        let trimmed = listName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Reject reserved name unless this IS the default list itself
        if PackingList.isReservedName(trimmed) && !(packingList?.isDefault ?? false) {
            return false
        }
        // Templates need an owner once there's more than one packer to choose from
        if isTemplate && users.count > 1 && owner == nil {
            return false
        }
        return true
    }
    
    var titleName: String {
        switch (isTemplate) {
            case true: return "Template"
            case false: return "Section"
        }
    }
    
    var titleString: String {
        return packingList == nil ? "Add \(self.titleName)" : "Edit \(self.titleName)"
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("\(self.titleName) Details") {
                    if packingList?.isDefault ?? false {
                        HStack {
                            Text("Name")
                            Spacer()
                            Text(listName)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        TextField("\(self.titleName) Name", text: $listName)
                    }

                    if isTemplate && users.count > 1 {
                        UserPickerView(selectedUser: $owner, style: .inline, allowAll: false)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(titleString)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        withAnimation {
                            save()
                            dismiss()
                        }
                    }.disabled(!formIsValid)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
            }

            if packingList != nil && !(packingList?.isDefault ?? false) {
                Button("Delete", role: .destructive) {
                    isDeleting.toggle()
                }
                .roundedBox()
                .shaded()
                .padding()
            }
        }
        .onAppear {
            if let packingList {
                listName = packingList.name
            }
            if isTemplate {
                owner = packingList?.user ?? users.first
            }
        }
        .alert("Delete \(packingList?.name ?? "section")?", isPresented: $isDeleting) {
            Button("Yes, delete \(packingList?.name ?? "section")", role: .destructive) {
                if let packingList {
                    delete(packingList)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if packingList?.appliedFromTemplate != nil {
                Text("This section will be removed from your trip. The template it was applied from will not be deleted.")
            }
        }
    }
    
    func save() {
        let newList = PackingList.save(
            packingList,
            name: listName,
            template: isTemplate,
            owner: isTemplate ? (owner ?? users.first) : nil,
            in: modelContext,
            for: trip
        )
        if let newList {
            onListCreated?(newList)
        }
    }
    
    private func delete(_ packingList: PackingList) {
        PackingList.delete(packingList, from: modelContext)
        isDeleted = true
        dismiss()
    }
}

@available(iOS 18.0, *)
#Preview(traits: .sampleData) {
    PackingListEditView(isDeleted: .constant(false))
        .previewDevice(PreviewDevice(rawValue: "iPhone 14"))
        .previewDisplayName("New Section")
}

@available(iOS 18.0, *)
#Preview(traits: .sampleData) {
    @Previewable @Query var lists: [PackingList]
    PackingListEditView(packingList: lists.first, isTemplate: true, isDeleted: .constant(false))
        .previewDevice(PreviewDevice(rawValue: "iPhone 14 Pro Max"))
        .previewDisplayName("Edit Section")
}
