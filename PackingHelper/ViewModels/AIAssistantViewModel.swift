//
//  AIAssistantViewModel.swift
//  PackingHelper
//
//  Drives the AI packing chat for one trip or template: sends the running conversation and
//  fresh context to the Worker, drops suggestions the user already has, inserts tapped
//  suggestions into the user's lists, and saves the conversation (`AIConversation`) until the
//  user starts a New Chat.
//

import Foundation
import SwiftData

@MainActor
@Observable
final class AIAssistantViewModel {
    struct ChatEntry: Identifiable, Codable {
        var id = UUID()
        let role: Role
        var text: String
        var suggestions: [AISuggestedItem]
        var addedNames: Set<String> = []

        enum Role: String, Codable { case user, assistant }
    }

    /// The trip, or the template being built
    let context: PackingListContext

    private(set) var entries: [ChatEntry] = []
    var composerText: String = ""
    private(set) var isLoading = false
    private(set) var remaining: Int?
    private(set) var resetsAt: Date?
    var errorMessage: String?
    /// Set when the Worker rejects us as unsubscribed even though the local
    /// gate let us in (stale CustomerInfo, e.g. a lapsed sandbox renewal).
    private(set) var subscriptionLapsed = false
    /// The packer new items go to; the sheet keeps it in sync with its picker (trip only)
    var targetUser: User?

    private var isPrepared = false
    private var weather: AIWeatherContext?
    /// Past trips, built on the first send and again only when the packer changes. Rebuilding
    /// them on every send would drop newly added items from them, which changes the prompt
    /// prefix the Worker caches; items already on the lists are dropped client-side anyway.
    private var pastTripsSnapshot: (packerID: PersistentIdentifier?, trips: [AIPastTrip])?
    private var modelContext: ModelContext?

    init(context: PackingListContext) {
        self.context = context
    }

    var isTemplate: Bool { !context.isTrip }

    var composerDisabled: Bool {
        isLoading || remaining == 0 || !isPrepared
    }

    /// Mirrors the Worker's `MAX_MESSAGES` limit; longer histories are rejected with a 400.
    private static let maxWireMessages = 40

    /// Loads the saved conversation and fetches weather, once per view model
    func prepare(modelContext: ModelContext) async {
        guard !isPrepared else { return }
        self.modelContext = modelContext
        entries = Self.decodeEntries(conversation?.entriesData)
        if let trip = context.trip {
            weather = await AITripContextBuilder.weatherContext(for: trip)
        }
        isPrepared = true
    }

    /// Sends `text`, or the composer's text when nil (starter prompts pass their own)
    func send(_ text: String? = nil) async {
        let prompt = (text ?? composerText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !composerDisabled else { return }

        let userEntry = ChatEntry(role: .user, text: prompt, suggestions: [])
        entries.append(userEntry)
        if text == nil { composerText = "" }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let request = makeRequest()
            let response = try await AIAssistantService.shared.sendMessage(request)
            entries.append(ChatEntry(
                role: .assistant,
                text: response.message,
                suggestions: resolvingListIDs(freshSuggestions(response.items), sentLists: request.tripContext?.lists)
            ))
            remaining = response.remaining
            save()
        } catch {
            // Take the message back out so the history never has two user turns in a row,
            // and put typed text back in the composer to retry (e.g. after subscribing). Starter
            // prompts stay out of it: their buttons come back with the empty state
            entries.removeAll { $0.id == userEntry.id }
            if text == nil, composerText.isEmpty { composerText = prompt }
            if let error = error as? AIAssistantError {
                handle(error)
            } else {
                errorMessage = AIAssistantError.network(error).errorDescription
            }
        }
    }

    /// Clears the saved conversation (the list menu's New Chat)
    func startNewChat() {
        entries = []
        composerText = ""
        errorMessage = nil
        pastTripsSnapshot = nil
        guard let conversation, let modelContext else { return }
        // Unlink first so a send before the next save makes a fresh conversation
        switch context {
        case .trip(let trip): trip.aiConversation = nil
        case .singleList(let list): list.aiConversation = nil
        }
        modelContext.delete(conversation)
    }

    /// Plus became active (bought from the paywall over the chat)
    func subscriptionRestored() {
        subscriptionLapsed = false
        errorMessage = nil
    }

    // MARK: - Adding suggestions

    /// Inserts one suggestion and marks it added. `list` overrides the
    /// automatic destination when the user picks one explicitly.
    func add(_ suggestion: AISuggestedItem, from entryID: UUID, to list: PackingList? = nil) {
        if !alreadyHas(suggestion), let list = list ?? destinationList(for: suggestion) {
            insert(suggestion, into: list)
        }
        markAdded(suggestion.name, in: entryID)
        save()
    }

    /// Inserts every not-yet-added suggestion from `suggestions` (one section
    /// of an entry).
    func addAll(_ suggestions: [AISuggestedItem], from entryID: UUID, to list: PackingList? = nil) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        for suggestion in suggestions
        where !entries[index].addedNames.contains(suggestion.name) {
            if !alreadyHas(suggestion), let list = list ?? destinationList(for: suggestion) {
                insert(suggestion, into: list)
            }
            entries[index].addedNames.insert(suggestion.name)
        }
        save()
    }

    /// Added from this reply, or already on the packer's lists (added by hand or from another reply)
    func isAdded(_ suggestion: AISuggestedItem, in entryID: UUID) -> Bool {
        let addedHere = entries.first(where: { $0.id == entryID })?.addedNames.contains(suggestion.name) ?? false
        return addedHere || alreadyHas(suggestion)
    }

    // MARK: - Private

    private var conversation: AIConversation? {
        switch context {
        case .trip(let trip): trip.aiConversation
        case .singleList(let list): list.aiConversation
        }
    }

    private func makeRequest() -> AIAssistantRequest {
        // The Worker rejects empty content and more than `maxWireMessages` entries, so drop
        // empty replies and send only the most recent window, starting on a user turn.
        var wireEntries = entries.filter { !$0.text.isEmpty }.suffix(Self.maxWireMessages)
        while let first = wireEntries.first, first.role != .user {
            wireEntries.removeFirst()
        }
        let messages: [AIChatMessageDTO] = wireEntries.map {
            AIChatMessageDTO(role: $0.role.rawValue, content: $0.text)
        }

        switch context {
        case .trip(let trip):
            return AIAssistantRequest(
                rcAppUserId: AITripContextBuilder.rcAppUserId,
                mode: .trip,
                tripContext: AITripContextBuilder.build(
                    for: trip,
                    targetUser: targetUser,
                    weather: weather,
                    pastTrips: pastTrips { AITripContextBuilder.pastTrips(for: trip, targetUser: targetUser) }
                ),
                templateContext: nil,
                messages: messages
            )
        case .singleList(let list):
            return AIAssistantRequest(
                rcAppUserId: AITripContextBuilder.rcAppUserId,
                mode: .template,
                tripContext: nil,
                templateContext: AITripContextBuilder.build(
                    for: list,
                    pastTrips: pastTrips { AITripContextBuilder.pastTrips(for: list) }
                ),
                messages: messages
            )
        }
    }

    /// The session's past trips for the current packer, built with `make` the first time
    private func pastTrips(_ make: () -> [AIPastTrip]) -> [AIPastTrip] {
        let packerID = isTemplate ? nil : targetUser?.persistentModelID
        if let pastTripsSnapshot, pastTripsSnapshot.packerID == packerID {
            return pastTripsSnapshot.trips
        }
        let trips = make()
        pastTripsSnapshot = (packerID, trips)
        return trips
    }

    /// Names already on the packer's lists (trip) or the template, as match keys
    private var existingKeys: Set<String> {
        let items: [Item]
        switch context {
        case .trip(let trip): items = AITripContextBuilder.itemsBelonging(to: targetUser, in: trip)
        case .singleList(let list): items = list.items ?? []
        }
        return Set(items.map { AITripContextBuilder.matchKey($0.name) })
    }

    private func alreadyHas(_ suggestion: AISuggestedItem) -> Bool {
        existingKeys.contains(AITripContextBuilder.matchKey(suggestion.name))
    }

    /// Drops suggestions the user already has and repeats within the reply, in case the model
    /// slips despite the prompt
    private func freshSuggestions(_ suggestions: [AISuggestedItem]) -> [AISuggestedItem] {
        var seen = existingKeys
        return suggestions.filter { seen.insert(AITripContextBuilder.matchKey($0.name)).inserted }
    }

    /// Swaps each short list id ("L2") for the UUID it stood for in the request that got this
    /// reply, so a saved chat keeps pointing at the right list after lists are added or moved.
    /// Unknown ids are cleared, and the suggestion falls back to the default destination
    private func resolvingListIDs(_ suggestions: [AISuggestedItem], sentLists: [AITripList]?) -> [AISuggestedItem] {
        guard let sentLists else { return suggestions }
        let uuids = Dictionary(sentLists.map { ($0.id.uppercased(), $0.listUUID) }, uniquingKeysWith: { first, _ in first })
        return suggestions.map { suggestion in
            var suggestion = suggestion
            suggestion.listId = suggestion.listId
                .flatMap { uuids[$0.trimmingCharacters(in: .whitespaces).uppercased()] }?
                .uuidString
            return suggestion
        }
    }

    private func insert(_ suggestion: AISuggestedItem, into list: PackingList) {
        guard let modelContext else { return }
        let item = Item(
            name: suggestion.name,
            category: suggestion.category.rawValue.capitalized,
            count: max(suggestion.count, 1),
            isPacked: false,
            sortOrder: SortOrderManager.nextSortOrder(for: list)
        )
        item.user = isTemplate ? nil : targetUser
        modelContext.insert(item)
        list.addItem(item)
    }

    /// Where tapping a suggestion puts it, for the row's caption (trip only). Matches
    /// `destinationList(for:)`, including a Default or Tasks list that tapping would create.
    func destination(for suggestion: AISuggestedItem) -> AISuggestionDestination? {
        guard case .trip(let trip) = context else { return nil }
        if let list = routedList(for: suggestion, in: trip) ?? fallbackList(for: suggestion, in: trip) {
            return AISuggestionDestination(name: list.name, kind: list.kind, isDayOf: list.isDayOf, isNew: false)
        }
        return suggestion.kind == .task
            ? AISuggestionDestination(name: "Tasks", kind: .tasks, isDayOf: false, isNew: true)
            : AISuggestionDestination(name: PackingList.defaultListName, kind: .packing, isDayOf: false, isNew: true)
    }

    /// Templates take everything. On a trip, the list the model picked, if it still exists and
    /// is the right kind; otherwise tasks go to the first everyday (not day-of) Tasks list and
    /// everything else to the trip's Default list, either made on first use if it's missing.
    /// Never another list: a toothbrush has no business on a Clothes list.
    private func destinationList(for suggestion: AISuggestedItem) -> PackingList? {
        switch context {
        case .singleList(let list):
            return list
        case .trip(let trip):
            if let list = routedList(for: suggestion, in: trip) ?? fallbackList(for: suggestion, in: trip) {
                return list
            }
            return suggestion.kind == .task ? makeTasksList(for: trip) : makeDefaultList(for: trip)
        }
    }

    /// The model's pick. Ignored when the list is gone (a saved chat), unknown, or the wrong kind
    private func routedList(for suggestion: AISuggestedItem, in trip: Trip) -> PackingList? {
        guard let listId = suggestion.listId, let id = UUID(uuidString: listId),
              let list = trip.lists?.first(where: { $0.uuid == id }) else { return nil }
        let kind: ListKind = suggestion.kind == .task ? .tasks : .packing
        return list.kind == kind ? list : nil
    }

    private func fallbackList(for suggestion: AISuggestedItem, in trip: Trip) -> PackingList? {
        if suggestion.kind == .task {
            return trip.sortedLists(of: .tasks).first { !$0.isDayOf }
        }
        return trip.defaultPackingList
    }

    private func makeTasksList(for trip: Trip) -> PackingList? {
        guard let modelContext else { return nil }
        let list = PackingList(kind: .tasks, template: false, name: "Tasks", countAsDays: false)
        modelContext.insert(list)
        trip.addList(list)
        return list
    }

    private func makeDefaultList(for trip: Trip) -> PackingList? {
        guard let modelContext else { return nil }
        return PackingList.createDefaultList(for: trip, in: modelContext)
    }

    private func markAdded(_ name: String, in entryID: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].addedNames.insert(name)
    }

    private func save() {
        guard let modelContext, !entries.isEmpty,
              let data = try? JSONEncoder().encode(entries) else { return }
        let conversation = conversation ?? makeConversation(in: modelContext)
        conversation.entriesData = data
        conversation.updated = .now
    }

    private func makeConversation(in modelContext: ModelContext) -> AIConversation {
        let conversation = AIConversation()
        modelContext.insert(conversation)
        switch context {
        case .trip(let trip): trip.aiConversation = conversation
        case .singleList(let list): list.aiConversation = conversation
        }
        return conversation
    }

    private static func decodeEntries(_ data: Data?) -> [ChatEntry] {
        guard let data, !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([ChatEntry].self, from: data)) ?? []
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
