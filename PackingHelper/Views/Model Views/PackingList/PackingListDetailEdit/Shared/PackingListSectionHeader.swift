//
//  PackingListSectionHeader.swift
//  PackingHelper
//
//  Created by Claude on 1/11/26.
//

import SwiftUI
import SwiftData

struct PackingListSectionHeader: View {
    let packingList: PackingList
    @Binding var isExpanded: Bool
    let onAddItem: () -> Void
    let onEditList: () -> Void
    let onDeleteList: () -> Void
    let onSaveAsDefault: () -> Void
    var onUpdateTemplate: (() -> Void)? = nil
    var isReorderMode: Bool = false

    private var isEmpty: Bool {
        packingList.items?.isEmpty ?? true
    }

    private var titleLabel: some View {
        HStack(spacing: 4) {
            Text(packingList.name)
                .font(.headline)
                .bold()
                .accessibilityAddTraits(.isHeader)

            if packingList.appliedFromTemplate != nil {
                Image(systemName: "square.on.square")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("From template")
            }
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            if isReorderMode {
                // Drag handle
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                titleLabel
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Chevron + name toggle the section; a Button so VoiceOver and Switch Control can use it
                Button {
                    withAnimation {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .rotationEffect(isExpanded ? .degrees(0) : .degrees(-90))
                            .contentTransition(.interpolate)
                            .foregroundStyle(.secondary)

                        titleLabel
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint(isExpanded ? "Collapses the section" : "Expands the section")
            }

            // Mini progress gauge
            TripDetailPackingProgressView(
                val: Double(packingList.completeItems.count),
                total: Double(packingList.totalItems),
                image: packingList.iconImage
            )
            .scaleEffect(0.6)
            .frame(width: 26, height: 26)

            // Add and Edit share one group so their 44pt hit areas sit edge to edge
            HStack(spacing: 0) {
                Button {
                    onAddItem()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .imageScale(.medium)
                        .foregroundStyle(.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add Item to \(packingList.name)")

                Button {
                    onEditList()
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .imageScale(.medium)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(packingList.name)")
            }
            // Pull the group's hit areas out to the trailing edge without moving the icons inward
            .padding(.trailing, -11)
        }
        .contentShape(Rectangle())
        .contextMenu {
            if !isReorderMode {
                Button {
                    onEditList()
                } label: {
                    Label("Edit List", systemImage: "pencil")
                }

                if let onUpdateTemplate, !packingList.templateCandidates.isEmpty {
                    Button(action: onUpdateTemplate) {
                        Label("Update Template…", systemImage: "square.and.arrow.down.on.square")
                    }
                }

                if !packingList.template && !packingList.isDefault {
                    Button {
                        onSaveAsDefault()
                    } label: {
                        Label("Save As Default", systemImage: "square.and.arrow.down")
                    }
                }

                if !packingList.isDefault {
                    Button(role: .destructive) {
                        onDeleteList()
                    } label: {
                        Label("Delete List", systemImage: "trash")
                    }
                }
            }
        }
    }
}
