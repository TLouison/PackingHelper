//
//  NewItemAccessoryBar.swift
//  PackingHelper
//
//  Sits directly above the keyboard while the inline new item row is focused: target list,
//  packer, and count. Reads and writes `PackingEditor`.
//

import SwiftUI

struct NewItemAccessoryBar: View {
    @Environment(PackingEditor.self) private var editor

    let isTrip: Bool
    let hasMultiplePackers: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isTrip {
                listPickerMenu
            }

            if hasMultiplePackers {
                UserPickerView(
                    selectedUser: Bindable(editor).user,
                    style: .menu,
                    allowAll: false
                )
            }

            Spacer()

            ItemCountStepper(count: Bindable(editor).count)
                .padding(.horizontal, 4)
                .opaqueGlassCapsule()
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var listPickerMenu: some View {
        Menu {
            ForEach(editor.sortedLists, id: \.id) { list in
                Button {
                    editor.targetList = list
                } label: {
                    if list.id == editor.targetList?.id {
                        Label(list.name, systemImage: "checkmark")
                    } else {
                        ListMenuLabel(list: list)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet")
                    .font(.caption)
                Text(editor.resolvedTargetList?.name ?? "Select List")
                    .fontWeight(.medium)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .opaqueGlassCapsule()
        }
        // Menus opening upward from the bottom reverse their items by default; keep section order
        .menuOrder(.fixed)
        .disabled(editor.lists.count <= 1)
    }
}
