//
//  PackingListContainerView+Sheets.swift
//  PackingHelper
//
//  Every sheet the packing container presents, behind one `.sheet(item:)`.
//

import SwiftUI

extension PackingListContainerView {
    enum ActiveSheet: Identifiable {
        /// Edit a trip list (trip context)
        case editList(PackingList)
        /// New list on the trip (trip context)
        case addList
        /// Apply a template to the trip (trip context)
        case applyTemplate
        /// The template's name and settings (single-list context)
        case listSettings
        /// The template's info (single-list context)
        case templateInfo
        /// The AI assistant as a sheet (templates, and trips at compact width)
        case aiAssistant

        var id: String {
            switch self {
            case .editList(let list): "editList-\(list.uuid.uuidString)"
            case .addList: "addList"
            case .applyTemplate: "applyTemplate"
            case .listSettings: "listSettings"
            case .templateInfo: "templateInfo"
            case .aiAssistant: "aiAssistant"
            }
        }

        var isAIAssistant: Bool {
            if case .aiAssistant = self { return true }
            return false
        }
    }

    @ViewBuilder
    func sheetContent(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .editList(let list):
            if let trip = context.trip {
                PackingListEditView(
                    packingList: list,
                    trip: trip,
                    isDeleted: .constant(false),
                    fitsContent: true
                )
            }
        case .addList:
            if let trip = context.trip {
                PackingListEditView(
                    packingList: nil,
                    trip: trip,
                    onListCreated: { newList in
                        editor.targetList = newList
                    }, isDeleted: .constant(false),
                    fitsContent: true
                )
            }
        case .applyTemplate:
            if let trip = context.trip {
                PackingListApplyDefaultView(trip: trip)
            }
        case .listSettings:
            if let singleList = context.singleList {
                PackingListEditView(
                    packingList: singleList,
                    isTemplate: singleList.template,
                    isDeleted: $isDeleted,
                    fitsContent: true
                )
            }
        case .templateInfo:
            if let singleList = context.singleList {
                TemplateListInfoView(list: singleList)
                    .presentationDetents([.fraction(0.65), .large])
            }
        case .aiAssistant:
            AIAssistantSheet(
                viewModel: assistantViewModel,
                users: users,
                targetUser: Bindable(editor).user
            )
            .presentationDetents([.large])
        }
    }
}
