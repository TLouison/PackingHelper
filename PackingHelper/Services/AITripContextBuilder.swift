//
//  AITripContextBuilder.swift
//  PackingHelper
//
//  Assembles the trip context sent to the AI assistant: core facts, existing
//  item names (for dedupe + accessory reasoning), and live weather when it's
//  available within the forecast window.
//

import Foundation
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

    static func build(for trip: Trip, targetUser: User?) async -> AITripContext {
        AITripContext(
            destinationName: trip.destination?.name ?? "",
            startDate: dayFormatter.string(from: trip.startDate),
            endDate: dayFormatter.string(from: trip.endDate),
            durationDays: max(trip.duration, 1),
            tripType: trip.typesName.lowercased(),
            accommodation: trip.accomodationsName.lowercased(),
            packerCount: max(trip.packers.count, 1),
            existingItems: existingItemNames(for: trip, targetUser: targetUser),
            weather: await weatherContext(for: trip)
        )
    }

    private static func existingItemNames(for trip: Trip, targetUser: User?) -> [String] {
        let items = trip.allItems.filter { item in
            guard let targetUser else { return true }
            return item.user?.persistentModelID == targetUser.persistentModelID
        }

        var seen = Set<String>()
        var names: [String] = []
        for item in items {
            let trimmed = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                names.append(trimmed)
            }
        }
        return names.sorted()
    }

    private static func weatherContext(for trip: Trip) async -> AIWeatherContext? {
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
