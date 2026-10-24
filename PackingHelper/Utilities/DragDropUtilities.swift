//
//  DragDropUtilities.swift
//  PackingHelper
//
//  Utilities for drag-and-drop functionality
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Custom UTTypes

extension UTType {
    static let packingItem = UTType(exportedAs: "com.packinghelper.item")
}

// MARK: - Item Transfer Data

/// Wrapper struct for transferring Item references during drag-and-drop
struct ItemTransferData: Codable, Transferable {
    let itemUUID: UUID  // Unique identifier for lookup
    let sourceListUUID: UUID?  // For cross-list moves

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .packingItem)
    }

    init(item: Item) {
        self.itemUUID = item.uuid
        self.sourceListUUID = item.list?.uuid
    }
}
