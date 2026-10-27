//
//  PackingListContainerView+Toolbar.swift
//  PackingHelper
//
//  The container's toolbars: trip, template, adding an item, and Remove Items mode.
//

import SwiftUI

extension PackingListContainerView {
    @ToolbarContentBuilder
    var containerToolbar: some ToolbarContent {
        if editor.isRemovingItems {
            removingItemsToolbar
        } else if editor.isAdding {
            addingItemToolbar
        } else if context.isTrip {
            tripToolbar
            addItemToolbar
        } else {
            singleListToolbar
            addItemToolbar
        }
    }

    /// Primary action lives in the bottom bar; on the folded iPhone Duo the system moves it to the side bar
    @ToolbarContentBuilder
    private var addItemToolbar: some ToolbarContent {
        // A trip with no sections has nowhere to put an item: create or apply one first
        if !(context.isTrip && lists.isEmpty) {
            ToolbarSpacer(placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button("Add Item", systemImage: "plus") {
                    editor.startAdding(in: nil)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var addingItemToolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            // Title + symbol so the system has a name to show in overflow menus and expanded bars
            Button { editor.finishAdding() } label: {
                Label("Done", systemImage: "checkmark")
                    .fontWeight(.semibold)
            }
        }
    }

    @ToolbarContentBuilder
    private var removingItemsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Undo", systemImage: "arrow.uturn.backward", action: editor.undoRemove)
                .disabled(editor.removedItems.isEmpty)
                .accessibilityHint(editor.removedItems.last.map { "Puts back \($0.name)" } ?? "")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button {
                editor.stopRemoving()
            } label: {
                Label("Done", systemImage: "checkmark")
                    .fontWeight(.semibold)
            }
        }
    }

    @ToolbarContentBuilder
    private var tripToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                if !purchaseManager.isPlusActive {
                    activeSheet = .aiPaywall
                } else if horizontalSizeClass == .regular {
                    if isShowingAssistantPanel {
                        closeAssistantPanel()
                    } else {
                        openAssistantPanel()
                    }
                } else {
                    assistantViewModel = AIAssistantViewModel()
                    activeSheet = .aiAssistant
                }
            } label: {
                Label {
                    Text("AI Packing Assistant")
                } icon: {
                    Image(systemName: "sparkles")
                        .overlay(alignment: .topTrailing) {
                            if !purchaseManager.isPlusActive {
                                Image(systemName: "plus.circle.fill")
                                    .font(.caption2)
                                    .imageScale(.small)
                                    .foregroundStyle(.white, .blue)
                                    .offset(x: 6, y: -6)
                                    .accessibilityHidden(true)
                            }
                        }
                }
            }
            .accessibilityHint(purchaseManager.isPlusActive ? "" : "Requires Packing Helper Plus")
        }
    }

    @ToolbarContentBuilder
    private var singleListToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                activeSheet = .templateInfo
            } label: {
                Label("List Info", systemImage: "info.circle")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                activeSheet = .listSettings
            } label: {
                Label("List Settings", systemImage: "gear")
            }
        }
    }
}
