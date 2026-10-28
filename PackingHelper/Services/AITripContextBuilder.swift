//
//  AITripContextBuilder.swift
//  PackingHelper
//
//  Assembles the context sent to the AI assistant: core trip facts, existing item names
//  (for dedupe + accessory reasoning), similar past trips (`AIPastTripsBuilder`), templates
//  that may fit (`AITemplateCandidatesBuilder`), and live
//  weather when it's available within the forecast window. Also the template-mode context and the item-name matching used to drop
//  suggestions the user already has.
//

import Foundation
import SwiftData
import WeatherKit
import RevenueCat

enum AITripContextBuilder {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// The stable RevenueCat app-user ID used for subscriber verification and
    /// usage metering on the Worker.
    static var rcAppUserId: String {
        Purchases.shared.appUserID
    }

    /// Built on every send so items added since the last message (by hand or from a
    /// suggestion) and packer changes are included. Weather and `pastTrips` come from the
    /// caller, which keeps them for the session so the Worker's cached prompt prefix holds.
    /// `offeredTemplates` are templates already offered in this chat, which aren't sent again.
    @MainActor
    static func build(
        for trip: Trip,
        targetUser: User?,
        weather: AIWeatherContext?,
        pastTrips: [AIPastTrip],
        offeredTemplates: Set<UUID>
    ) -> AITripContext {
        // With multiple packers off, the trip is packed as one person's
        let multiplePackers = FeatureFlags.shared.showingMultiplePackers
        let targetUser = multiplePackers ? targetUser : nil
        let mine = itemsBelonging(to: targetUser, in: trip)
        let mineKeys = Set(mine.map(\.name).map(matchKey))
        let others = trip.allItems.filter { item in
            guard let targetUser, let user = item.user else { return false }
            return user.persistentModelID != targetUser.persistentModelID
        }

        return AITripContext(
            tripName: trip.name,
            destinationName: trip.destination?.name ?? "",
            destinationLatitude: trip.destination?.latitude,
            originName: trip.origin?.name,
            startDate: dayFormatter.string(from: trip.startDate),
            endDate: dayFormatter.string(from: trip.endDate),
            durationDays: max(trip.duration, 1),
            tripType: trip.typesName.lowercased(),
            accommodation: trip.accomodationsName.lowercased(),
            packerCount: multiplePackers ? max(trip.packers.count, 1) : 1,
            lists: tripLists(for: trip, items: mine),
            otherPackersItems: uniqueNames(others).filter { !mineKeys.contains(matchKey($0)) },
            pastTrips: pastTrips,
            templateCandidates: AITemplateCandidatesBuilder.build(for: trip, targetUser: targetUser, excluding: offeredTemplates),
            weather: weather
        )
    }

    @MainActor
    static func build(for template: PackingList, pastTrips: [AIPastTrip]) -> AITemplateContext {
        AITemplateContext(
            name: template.name,
            listKind: template.kind.rawValue,
            isDayOf: template.isDayOf,
            countAsDays: template.countAsDays,
            existingItems: uniqueNames(template.items ?? []),
            pastTrips: pastTrips
        )
    }

    /// The packer's most similar other trips, minus what's on their lists right now
    @MainActor
    static func pastTrips(for trip: Trip, targetUser: User?) -> [AIPastTrip] {
        let targetUser = FeatureFlags.shared.showingMultiplePackers ? targetUser : nil
        let mineKeys = Set(itemsBelonging(to: targetUser, in: trip).map(\.name).map(matchKey))
        return AIPastTripsBuilder.build(similarTo: trip, targetUser: targetUser, excluding: mineKeys)
    }

    @MainActor
    static func pastTrips(for template: PackingList) -> [AIPastTrip] {
        AIPastTripsBuilder.build(for: template, excluding: Set((template.items ?? []).map(\.name).map(matchKey)))
    }

    /// Every list, including ones with none of `items` (an empty Beach list can still take suggestions)
    @MainActor
    private static func tripLists(for trip: Trip, items: [Item]) -> [AITripList] {
        let included = Set(items.map(\.persistentModelID))
        return PackingList.sorted(trip.lists ?? [], sortOrder: .byCustomOrder).enumerated().map { index, list in
            var seen = Set<String>()
            let names = (list.items ?? [])
                .filter { included.contains($0.persistentModelID) }
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && seen.insert(matchKey($0)).inserted }
            return AITripList(
                id: "L\(index + 1)",
                listUUID: list.uuid,
                name: list.name,
                kind: list.kind.rawValue,
                isDayOf: list.isDayOf,
                isDefault: list.isDefault,
                fromTemplate: list.appliedFromTemplate?.name,
                items: names
            )
        }
    }

    /// The packer's items plus unassigned ones (everything when there's no packer)
    @MainActor
    static func itemsBelonging(to targetUser: User?, in trip: Trip) -> [Item] {
        trip.allItems.filter { item in
            guard let targetUser, let user = item.user else { return true }
            return user.persistentModelID == targetUser.persistentModelID
        }
    }

    /// Loose identity for item names so "Phone Chargers" matches "phone charger"
    static func matchKey(_ name: String) -> String {
        var key = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if key.count > 3, key.hasSuffix("s"), !key.hasSuffix("ss") {
            key.removeLast()
        }
        return key
    }

    @MainActor
    private static func uniqueNames(_ items: [Item]) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for item in items {
            let trimmed = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(matchKey(trimmed)).inserted {
                names.append(trimmed)
            }
        }
        return names.sorted()
    }

    @MainActor
    static func weatherContext(for trip: Trip) async -> AIWeatherContext? {
        guard let destination = trip.destination,
              let weather = await destination.getTripWeather(for: trip) else {
            return nil
        }

        let currentC = weather.getCurrentTemperature(in: .celsius)?.value
        let daily: [AIDailyWeather] = (weather.dailyForecast?.forecast ?? []).map { day in
            AIDailyWeather(
                day: dayFormatter.string(from: day.date),
                highC: day.highTemperature.converted(to: .celsius).value.rounded(),
                lowC: day.lowTemperature.converted(to: .celsius).value.rounded(),
                condition: day.condition.description
            )
        }

        // Nothing usable → omit weather entirely so the model advises generally.
        guard currentC != nil || !daily.isEmpty else { return nil }

        return AIWeatherContext(currentTempC: (currentC ?? 0).rounded(), daily: daily)
    }
}
