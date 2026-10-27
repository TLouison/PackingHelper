//
//  AIConversation.swift
//  PackingHelper
//
//  The saved AI assistant chat for one trip or template. Kept until the user starts a
//  New Chat; deleted with its trip or template.
//

import Foundation
import SwiftData

@Model
final class AIConversation {
    var uuid: UUID = UUID()
    var updated: Date = Date.now

    /// JSON-encoded `[AIAssistantViewModel.ChatEntry]`. One blob, since the chat is only
    /// ever read and written whole.
    var entriesData: Data = Data()

    var trip: Trip?
    var template: PackingList?

    init() {}
}
