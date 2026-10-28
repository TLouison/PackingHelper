//
//  AIPastTripsBuilder.swift
//  PackingHelper
//
//  Picks the user's other trips most like the one being packed (or most relevant to a
//  template) and summarizes what the packer brought on each, including items added on that
//  trip that never made it into a template. The assistant uses these as personal signals
//  ("you brought trail mix on your last beach trip").
//

import CoreLocation
import Foundation
import SwiftData

enum AIPastTripsBuilder {
    /// Enough to spot habits without crowding the prompt
    private static let maxTrips = 6
    private static let maxItemsPerTrip = 80

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f
    }()

    /// Other trips ranked by similarity to `trip`, skipping items already on it
    @MainActor
    static func build(similarTo trip: Trip, targetUser: User?, excluding existingKeys: Set<String>) -> [AIPastTrip] {
        let candidates = otherTrips(in: trip.modelContext).filter { $0.uuid != trip.uuid }
        let tripListKeys = Set((trip.lists ?? []).map { AITripContextBuilder.matchKey($0.name) })
        let ranked = candidates
            .map { ($0, similarity(of: $0, to: trip, listKeys: tripListKeys)) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.startDate > $1.0.startDate }
            .map(\.0)
        return summaries(of: ranked, targetUser: targetUser, excluding: existingKeys)
    }

    /// Trips this template was applied to first, then trips with a similarly named list, then
    /// the most recent; skips items already on the template
    @MainActor
    static func build(for template: PackingList, excluding existingKeys: Set<String>) -> [AIPastTrip] {
        let appliedTripIDs = Set((template.appliedToLists ?? []).compactMap { $0.trip?.uuid })
        let nameKey = AITripContextBuilder.matchKey(template.name)
        let ranked = otherTrips(in: template.modelContext)
            .map { trip -> (Trip, Int) in
                var score = appliedTripIDs.contains(trip.uuid) ? 5 : 0
                if (trip.lists ?? []).contains(where: { AITripContextBuilder.matchKey($0.name) == nameKey }) {
                    score += 3
                }
                return (trip, score)
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.startDate > $1.0.startDate }
            .map(\.0)
        // Templates have no packer; every packer's items count
        return summaries(of: ranked, targetUser: nil, excluding: existingKeys)
    }

    // MARK: - Private

    @MainActor
    private static func otherTrips(in modelContext: ModelContext?) -> [Trip] {
        guard let modelContext else { return [] }
        return (try? modelContext.fetch(FetchDescriptor<Trip>())) ?? []
    }

    /// Higher is more alike: same place, season and climate, transport, stays, and list names
    /// (a "Beach" list on both says more than anything else)
    @MainActor
    private static func similarity(of other: Trip, to trip: Trip, listKeys: Set<String>) -> Int {
        var score = 0

        if let a = trip.destination, let b = other.destination {
            let distance = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            if distance < 50_000 {
                score += 5
            } else if distance < 500_000 {
                score += 3
            }
            // Similar climate: comparable latitude in the same hemisphere, within a month of the season
            let sameHemisphere = (a.latitude >= 0) == (b.latitude >= 0)
            if sameHemisphere && abs(a.latitude - b.latitude) < 15
                && monthsApart(trip.startDate, other.startDate) <= 1 {
                score += 2
            }
        }

        score += Set(trip.types).intersection(other.types).count
        score += Set(trip.accomodations).intersection(other.accomodations).count
        let otherListKeys = Set((other.lists ?? []).filter { !$0.isDefault }.map { AITripContextBuilder.matchKey($0.name) })
        score += 2 * listKeys.intersection(otherListKeys).count

        return score
    }

    /// Calendar months apart, ignoring the year (December and January are 1 apart)
    private static func monthsApart(_ a: Date, _ b: Date) -> Int {
        let calendar = Calendar.current
        let diff = abs(calendar.component(.month, from: a) - calendar.component(.month, from: b))
        return min(diff, 12 - diff)
    }

    @MainActor
    private static func summaries(of trips: [Trip], targetUser: User?, excluding existingKeys: Set<String>) -> [AIPastTrip] {
        var result: [AIPastTrip] = []
        for trip in trips {
            guard result.count < maxTrips else { break }
            if let summary = summary(of: trip, targetUser: targetUser, excluding: existingKeys) {
                result.append(summary)
            }
        }
        return result
    }

    /// nil when the packer had nothing new on that trip
    @MainActor
    private static func summary(of trip: Trip, targetUser: User?, excluding existingKeys: Set<String>) -> AIPastTrip? {
        let mine = Set(AITripContextBuilder.itemsBelonging(to: targetUser, in: trip).map(\.persistentModelID))
        var budget = maxItemsPerTrip
        var seen = existingKeys
        var lists: [AIPastTripList] = []

        for list in PackingList.sorted(trip.lists ?? [], sortOrder: .byCustomOrder) {
            guard budget > 0 else { break }
            var names: [String] = []
            for item in (list.items ?? []).sorted(by: { $0.sortOrder < $1.sortOrder })
            where mine.contains(item.persistentModelID) && budget > 0 {
                let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, seen.insert(AITripContextBuilder.matchKey(name)).inserted else { continue }
                names.append(name)
                budget -= 1
            }
            guard !names.isEmpty else { continue }
            lists.append(AIPastTripList(
                name: list.name,
                kind: list.kind.rawValue,
                fromTemplate: list.appliedFromTemplate?.name,
                items: names
            ))
        }
        guard !lists.isEmpty else { return nil }

        return AIPastTrip(
            name: trip.name,
            destinationName: trip.destination?.name ?? "",
            month: monthFormatter.string(from: trip.startDate),
            durationDays: max(trip.duration, 1),
            tripType: trip.typesName.lowercased(),
            accommodation: trip.accomodationsName.lowercased(),
            lists: lists
        )
    }
}
