//
//  AIAssistantViewModel.swift
//  PackingHelper
//
//  Drives the ephemeral AI packing chat: builds trip context once per session,
//  sends the running conversation to the Worker, and inserts tapped suggestions
//  into the user's lists.
//

import Foundation
import SwiftData

@MainActor
@Observable
final class AIAssistantViewModel {
    struct ChatEntry: Identifiable {
        let id = UUID()
        let role: Role
        var text: String
        var suggestions: [AISuggestedItem]
        var addedNames: Set<String> = []

        enum Role { case user, assistant }
    }

    private(set) var entries: [ChatEntry] = []
    var composerText: String = ""
    private(set) var isLoading = false
    private(set) var remaining: Int?
    private(set) var resetsAt: Date?
    var errorMessage: String?
    /// Set when the Worker rejects us as unsubscribed even though the local
    /// gate let us in (stale CustomerInfo, e.g. a lapsed sandbox renewal).
    private(set) var subscriptionLapsed = false

    private var tripContext: AITripContext?
    private var contextReady = false

    // Session dependencies, injected in prepare().
    private var trip: Trip?
    private weak var targetUser: User?
    private var modelContext: ModelContext?

    var composerDisabled: Bool {
        isLoading || remaining == 0 || !contextReady
    }

    /// Mirrors the Worker's `MAX_MESSAGES` limit; longer histories are rejected with a 400.
    private static let maxWireMessages = 40

    /// Builds the trip context once (async — includes the weather fetch).
    func prepare(trip: Trip, targetUser: User?, modelContext: ModelContext) async {
        guard !contextReady else { return }
        self.trip = trip
        self.targetUser = targetUser
        self.modelContext = modelContext
        self.tripContext = await AITripContextBuilder.build(for: trip, targetUser: targetUser)
        self.contextReady = true
    }

    func send() async {
        let prompt = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !composerDisabled, let tripContext else { return }

        entries.append(ChatEntry(role: .user, text: prompt, suggestions: []))
        composerText = ""
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        // The Worker rejects empty content and more than `maxWireMessages` entries, so drop
        // empty replies and send only the most recent window, starting on a user turn.
        var wireEntries = entries.filter { !$0.text.isEmpty }.suffix(Self.maxWireMessages)
        while let first = wireEntries.first, first.role != .user {
            wireEntries.removeFirst()
        }
        let wireMessages: [AIChatMessageDTO] = wireEntries.map {
            AIChatMessageDTO(role: $0.role == .user ? "user" : "assistant", content: $0.text)
        }

        let request = AIAssistantRequest(
            rcAppUserId: AITripContextBuilder.rcAppUserId,
            tripContext: tripContext,
            messages: wireMessages
        )

        do {
            let response = try await AIAssistantService.shared.sendMessage(request)
            entries.append(ChatEntry(
                role: .assistant,
                text: response.message,
                suggestions: response.items
            ))
            remaining = response.remaining
        } catch let error as AIAssistantError {
            handle(error)
        } catch {
            errorMessage = AIAssistantError.network(error).errorDescription
        }
    }

    // MARK: - Adding suggestions

    /// Inserts one suggestion and marks it added. `list` overrides the
    /// automatic destination when the user picks one explicitly.
    func add(_ suggestion: AISuggestedItem, from entryID: UUID, to list: PackingList? = nil) {
        guard let list = list ?? destinationList(for: suggestion) else { return }
        insert(suggestion, into: list)
        markAdded(suggestion.name, in: entryID)
    }

    /// Inserts every not-yet-added suggestion from `suggestions` (one section
    /// of an entry).
    func addAll(_ suggestions: [AISuggestedItem], from entryID: UUID, to list: PackingList? = nil) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        for suggestion in suggestions
        where !entries[index].addedNames.contains(suggestion.name) {
            if let list = list ?? destinationList(for: suggestion) {
                insert(suggestion, into: list)
                entries[index].addedNames.insert(suggestion.name)
            }
        }
    }

    func isAdded(_ suggestion: AISuggestedItem, in entryID: UUID) -> Bool {
        entries.first(where: { $0.id == entryID })?.addedNames.contains(suggestion.name) ?? false
    }

    // MARK: - Private

    private func insert(_ suggestion: AISuggestedItem, into list: PackingList) {
        guard let modelContext else { return }
        let item = Item(
            name: suggestion.name,
            category: suggestion.category.rawValue.capitalized,
            count: max(suggestion.count, 1),
            isPacked: false,
            sortOrder: SortOrderManager.nextSortOrder(for: list)
        )
        item.user = targetUser
        modelContext.insert(item)
        list.addItem(item)
    }

    /// Task suggestions go to the trip's first everyday (not day-of) Tasks list, made on
    /// first use if there isn't one; everything else goes to the trip's default list.
    private func destinationList(for suggestion: AISuggestedItem) -> PackingList? {
        guard let trip else { return nil }
        if suggestion.kind == .task {
            return trip.sortedLists(of: .tasks).first { !$0.isDayOf } ?? makeTasksList(for: trip)
        }
        return trip.defaultPackingList ?? trip.lists?.first
    }

    private func makeTasksList(for trip: Trip) -> PackingList? {
        guard let modelContext else { return nil }
        let list = PackingList(kind: .tasks, template: false, name: "Tasks", countAsDays: false)
        modelContext.insert(list)
        trip.addList(list)
        return list
    }

    private func markAdded(_ name: String, in entryID: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].addedNames.insert(name)
    }

    private func handle(_ error: AIAssistantError) {
        switch error {
        case .limitReached(let resetsAt):
            remaining = 0
            self.resetsAt = resetsAt
        case .notSubscribed:
            subscriptionLapsed = true
        default:
            break
        }
        errorMessage = error.errorDescription
    }
}
