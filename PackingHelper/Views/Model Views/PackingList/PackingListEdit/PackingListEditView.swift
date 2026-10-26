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
    @State private var kind: ListKind = .packing
    @State private var isDayOf = false
    @FocusState private var isNameFocused: Bool
    @State private var owner: User?

    @State private var isDeleting: Bool = false
    @Binding var isDeleted: Bool

    /// Sizes the sheet to the form instead of a fixed detent (name and type, plus owner and delete)
    var fitsContent: Bool = false
    /// Form content plus the nav bar, measured for `fitsContent`
    @State private var fittedHeight: CGFloat?
    
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
            case false: return "List"
        }
    }
    
    var titleString: String {
        return packingList == nil ? "Add \(self.titleName)" : "Edit \(self.titleName)"
    }
    
    var body: some View {
        if fitsContent {
            // .medium until the form has been measured
            content.presentationDetents([fittedHeight.map { PresentationDetent.height($0) } ?? .medium])
        } else {
            content
        }
    }

    private var content: some View {
        NavigationStack {
            Form {
                Section {
                    if packingList?.isDefault ?? false {
                        LabeledContent("Name", value: listName)
                    } else {
                        LabeledContent("Name") {
                            TextField("\(self.titleName) Name", text: $listName)
                                .multilineTextAlignment(.trailing)
                                .focused($isNameFocused)
                                .submitLabel(.done)
                                .onSubmit(saveAndDismiss)
                                .task {
                                    // New lists and templates start typing right away. Focus once the
                                    // sheet has finished presenting; setting it in onAppear is dropped
                                    // because the Form's row isn't in the hierarchy yet.
                                    guard packingList == nil else { return }
                                    try? await Task.sleep(for: .milliseconds(350))
                                    isNameFocused = true
                                }
                        }
                    }

                    // The Default list is always an everyday packing list
                    if !(packingList?.isDefault ?? false) {
                        Picker("Type", selection: $kind) {
                            ForEach(ListKind.allCases) { kind in
                                Text(kind.name).tag(kind)
                            }
                        }
                        .pickerStyle(.menu)

                        Toggle("Day Of", isOn: $isDayOf)
                    }

                    if isTemplate && users.count > 1 {
                        UserPickerView(selectedUser: $owner, style: .inline, allowAll: false)
                    }
                } header: {
                    Text("\(self.titleName) Details")
                } footer: {
                    if !(packingList?.isDefault ?? false) {
                        Text("Day Of lists hold what you can't do or pack ahead. They stay at the end of your lists.")
                    }
                }

                if packingList != nil {
                    Section {
                        Button("Delete \(titleName)", role: .destructive) {
                            isDeleting.toggle()
                        }
                    }
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                // Top inset is the nav bar; the keyboard's bottom inset is left out so focusing doesn't resize the sheet
                geometry.contentSize.height + geometry.contentInsets.top
            } action: { _, height in
                if fitsContent { fittedHeight = height + 16 }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(titleString)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveAndDismiss)
                        .disabled(!formIsValid)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
            }

        }
        .onAppear {
            if let packingList {
                listName = packingList.name
                kind = packingList.kind
                isDayOf = packingList.isDayOf
            }
            if isTemplate {
                owner = packingList?.user ?? users.first
            }
        }
        .alert("Delete \(packingList?.name ?? "list")?", isPresented: $isDeleting) {
            Button("Yes, delete \(packingList?.name ?? "list")", role: .destructive) {
                if let packingList {
                    delete(packingList)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if packingList?.appliedFromTemplate != nil {
                Text("This list will be removed from your trip. The template it was applied from will not be deleted.")
            }
        }
    }
    
    private func saveAndDismiss() {
        guard formIsValid else { return }
        isNameFocused = false
        withAnimation {
            save()
            dismiss()
        }
    }

    func save() {
        let newList = PackingList.save(
            packingList,
            name: listName,
            template: isTemplate,
            kind: kind,
            isDayOf: isDayOf,
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
        .previewDisplayName("New List")
}

@available(iOS 18.0, *)
#Preview(traits: .sampleData) {
    @Previewable @Query var lists: [PackingList]
    PackingListEditView(packingList: lists.first, isTemplate: true, isDeleted: .constant(false))
        .previewDevice(PreviewDevice(rawValue: "iPhone 14 Pro Max"))
        .previewDisplayName("Edit Template")
}
