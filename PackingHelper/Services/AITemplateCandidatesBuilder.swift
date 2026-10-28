//
//  AITemplateCandidatesBuilder.swift
//  PackingHelper
//
//  Picks the user's templates that could be offered on a trip in the AI assistant. The bar is
//  high: a template is sent only with a hard reason it may fit (used on a similar trip, its
//  name matches the trip or a list, or much of it is already on the trip), and the model then
//  offers at most one, usually none.
//

import Foundation
import SwiftData

enum AITemplateCandidatesBuilder {
    private static let maxCandidates = 5
    /// Candidates are paid at full input price on every send, so each sends only its first items
    private static let maxItemsPerCandidate = 25
    /// Item overlap counts only with at least this many and this share of the template's items
    private static let minOverlapCount = 4
    private static let minOverlapShare = 0.4

    /// Words that say nothing about what a template is for ("Weekend Essentials")
    private static let stopWords: Set<String> = [
        "trip", "list", "packing", "pack", "travel", "stuff", "my", "the", "and", "for",
        "weekend", "week", "day", "essential", "basic", "general", "misc", "thing",
    ]

    /// Strongest first, ids "T1"… in that order. `excluding` holds templates already offered in
    /// this chat (added or dismissed), which are never offered again.
    @MainActor
    static func build(for trip: Trip, targetUser: User?, excluding offered: Set<UUID> = []) -> [AITemplateCandidate] {
        let targetUser = FeatureFlags.shared.showingMultiplePackers ? targetUser : nil
        let ranked = templates(in: trip.modelContext)
            .filter { !offered.contains($0.uuid) && isEligible($0, for: trip, targetUser: targetUser) }
            .compactMap { scored($0, for: trip, targetUser: targetUser) }
            .sorted { a, b in
                if a.strength != b.strength { return a.strength > b.strength }
                if a.lastUsed != b.lastUsed { return (a.lastUsed ?? .distantPast) > (b.lastUsed ?? .distantPast) }
                return a.template.name.localizedStandardCompare(b.template.name) == .orderedAscending
            }
            .prefix(maxCandidates)

        return ranked.enumerated().map { index, candidate in
            let template = candidate.template
            let items = (template.items ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return AITemplateCandidate(
                id: "T\(index + 1)",
                templateUUID: template.uuid,
                name: template.name,
                kind: template.kind.rawValue,
                isDayOf: template.isDayOf,
                itemCount: items.count,
                items: Array(items.prefix(maxItemsPerCandidate)),
                signals: candidate.signals
            )
        }
    }

    /// Why `template` can't be added to `trip` for `targetUser` right now, or nil when it can.
    /// Re-checked when an offer is shown and tapped, since lists and the packer change mid-chat
    @MainActor
    static func unavailableReason(for template: PackingList, on trip: Trip, targetUser: User?) -> UnavailableReason? {
        let targetUser = FeatureFlags.shared.showingMultiplePackers ? targetUser : nil
        if isOnTrip(template, trip) { return .alreadyOnTrip }
        if !isOwned(template, by: targetUser) || (template.items ?? []).isEmpty { return .gone }
        return nil
    }

    enum UnavailableReason {
        /// Applied already, or the trip has a list with its name
        case alreadyOnTrip
        /// Deleted, emptied, or another packer's
        case gone
    }

    /// Who an added template's items go to: an owned template's owner, else the packer
    @MainActor
    static func recipient(of template: PackingList, targetUser: User?) -> User? {
        FeatureFlags.shared.showingMultiplePackers ? (template.user ?? targetUser) : nil
    }

    // MARK: - Private

    private struct Scored {
        let template: PackingList
        let strength: Int
        let signals: [String]
        /// Start of the most recent other trip it was applied to
        let lastUsed: Date?
    }

    @MainActor
    private static func templates(in modelContext: ModelContext?) -> [PackingList] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<PackingList>(predicate: #Predicate { $0.template == true })
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    @MainActor
    private static func isEligible(_ template: PackingList, for trip: Trip, targetUser: User?) -> Bool {
        !(template.items ?? []).isEmpty && !isOnTrip(template, trip) && isOwned(template, by: targetUser)
    }

    /// Applied to the trip already, or a trip list has its name
    @MainActor
    private static func isOnTrip(_ template: PackingList, _ trip: Trip) -> Bool {
        let nameKey = AITripContextBuilder.matchKey(template.name)
        return (trip.lists ?? []).contains { list in
            list.appliedFromTemplate?.uuid == template.uuid || AITripContextBuilder.matchKey(list.name) == nameKey
        }
    }

    /// An owned template's items go to its owner, so another packer's would land on the wrong person
    @MainActor
    private static func isOwned(_ template: PackingList, by targetUser: User?) -> Bool {
        guard let owner = template.user, let targetUser else { return true }
        return owner.persistentModelID == targetUser.persistentModelID
    }

    /// nil when there's no hard reason it fits
    @MainActor
    private static func scored(_ template: PackingList, for trip: Trip, targetUser: User?) -> Scored? {
        var strength = 0
        var signals: [String] = []

        // Past use: applied to another trip much like this one
        let otherTrips = (template.appliedToLists ?? [])
            .compactMap(\.trip)
            .filter { $0.uuid != trip.uuid }
        let lastUsed = otherTrips.map(\.startDate).max()
        let tripListKeys = Set((trip.lists ?? []).map { AITripContextBuilder.matchKey($0.name) })
        let similar = otherTrips
            .map { ($0, AIPastTripsBuilder.similarity(of: $0, to: trip, listKeys: tripListKeys)) }
            .filter { $0.1 >= AIPastTripsBuilder.similarTripScore }
            .max { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.startDate < $1.0.startDate }
        if let similarTrip = similar?.0 {
            strength += 3
            signals.append("used on \"\(similarTrip.name)\", a similar trip")
        }

        // Name match: a meaningful word of its name in the trip name or a list name
        let nameTokens = significantTokens(template.name)
        if !nameTokens.isEmpty {
            if !nameTokens.isDisjoint(with: significantTokens(trip.name)) {
                strength += 2
                signals.append("name matches the trip name")
            } else if let list = PackingList.sorted(trip.lists ?? [], sortOrder: .byCustomOrder)
                .first(where: { !$0.isDefault && !nameTokens.isDisjoint(with: significantTokens($0.name)) }) {
                strength += 2
                signals.append("name matches list \"\(list.name)\"")
            }
        }

        // Item overlap: much of it is already on the trip
        let templateKeys = Set((template.items ?? []).map { AITripContextBuilder.matchKey($0.name) }.filter { !$0.isEmpty })
        let recipient = recipient(of: template, targetUser: targetUser)
        let tripKeys = Set(AITripContextBuilder.itemsBelonging(to: recipient, in: trip).map { AITripContextBuilder.matchKey($0.name) })
        let overlap = templateKeys.intersection(tripKeys).count
        if overlap >= minOverlapCount, Double(overlap) >= minOverlapShare * Double(templateKeys.count) {
            strength += 1
            signals.append("\(overlap) of \(templateKeys.count) items already on this trip")
        }

        guard strength > 0 else { return nil }
        return Scored(template: template, strength: strength, signals: signals, lastUsed: lastUsed)
    }

    /// The words of `name` that say what it's for, plurals trimmed ("Beach Towels" → beach, towel)
    private static func significantTokens(_ name: String) -> Set<String> {
        let tokens = AITripContextBuilder.matchKey(name)
            .split(separator: " ")
            .map { token -> String in
                var token = String(token)
                if token.count > 3, token.hasSuffix("s"), !token.hasSuffix("ss") {
                    token.removeLast()
                }
                return token
            }
            .filter { $0.count >= 3 && !stopWords.contains($0) }
        return Set(tokens)
    }
}
