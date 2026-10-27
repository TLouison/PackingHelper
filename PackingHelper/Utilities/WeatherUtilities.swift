//
//  WeatherUtilities.swift
//  PackingHelper
//
//  Created by Todd Louison on 5/22/24.
//

import CoreLocation
import Foundation
import WeatherKit

struct TripWeather {
    let currentWeather: CurrentWeather?
    let dailyForecast: Forecast<DayWeather>?
    
    func getCurrentTemperature(in unit: UnitTemperature = .celsius) -> Measurement<UnitTemperature>? {
        if let currentWeather {
            return currentWeather.temperature
                .converted(to: unit)
        }
        return nil
    }
}

func getCurrentWeatherFormattedTemperature(currentTemperature: Measurement<UnitTemperature>) -> String {
    return currentTemperature.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(.zero))))
}

/// Fetches WeatherKit data off the main actor and caches it for an hour.
///
/// Takes plain values (never models) and keeps a single `WeatherService`. Only
/// results that carry data are cached, so failures and empty answers retry on
/// the next request. The cache is keyed by place and trip dates, so editing
/// either fetches fresh data.
actor WeatherProvider {
    static let shared = WeatherProvider()

    /// How long a cached result is reused
    private static let timeToLive: TimeInterval = SECONDS_IN_MINUTE * MINUTES_IN_HOUR
    /// Length of the forecast window, in days
    private static let forecastDays: Double = 5

    private struct Key: Hashable {
        let latitude: Double
        let longitude: Double
        let tripStart: Date
        let tripEnd: Date
    }

    private let service = WeatherService()
    private var cache: [Key: (weather: TripWeather, fetched: Date)] = [:]

    func currentWeather(latitude: Double, longitude: Double) async -> CurrentWeather? {
        try? await service.weather(for: CLLocation(latitude: latitude, longitude: longitude)).currentWeather
    }

    func forecast(latitude: Double, longitude: Double, tripStart: Date) async -> Forecast<DayWeather>? {
        let (startDate, endDate) = Self.forecastWindow(tripStart: tripStart)
        return try? await service.weather(
            for: CLLocation(latitude: latitude, longitude: longitude),
            including: .daily(startDate: startDate, endDate: endDate)
        )
    }

    /// Current conditions and/or the forecast, whichever the caller allows. Nil when the combined fetch fails.
    func tripWeather(
        latitude: Double,
        longitude: Double,
        tripStart: Date,
        tripEnd: Date,
        allowCurrent: Bool,
        allowForecast: Bool
    ) async -> TripWeather? {
        let key = Key(latitude: latitude, longitude: longitude, tripStart: tripStart, tripEnd: max(tripStart, tripEnd))
        if let cached = cache[key], cached.fetched.distance(to: .now) < Self.timeToLive {
            return cached.weather
        }

        let newWeather: TripWeather
        if allowCurrent && allowForecast {
            AppLogger.weather.debug("Fetching current weather + 5-day forecast")
            let (startDate, endDate) = Self.forecastWindow(tripStart: tripStart)
            do {
                let data = try await service.weather(
                    for: CLLocation(latitude: latitude, longitude: longitude),
                    including: .daily(startDate: startDate, endDate: endDate),
                    .current
                )
                newWeather = TripWeather(currentWeather: data.1, dailyForecast: data.0)
            } catch {
                AppLogger.weather.error("Failed to fetch weather: \(error.localizedDescription)")
                return nil
            }
        } else if allowCurrent {
            AppLogger.weather.debug("Fetching current weather only")
            newWeather = TripWeather(
                currentWeather: await currentWeather(latitude: latitude, longitude: longitude),
                dailyForecast: nil
            )
        } else if allowForecast {
            AppLogger.weather.debug("Fetching forecast weather only")
            newWeather = TripWeather(
                currentWeather: nil,
                dailyForecast: await forecast(latitude: latitude, longitude: longitude, tripStart: tripStart)
            )
        } else {
            AppLogger.weather.debug("No weather data available for this trip")
            newWeather = TripWeather(currentWeather: nil, dailyForecast: nil)
        }

        if newWeather.currentWeather != nil || newWeather.dailyForecast != nil {
            cache[key] = (newWeather, .now)
        }
        return newWeather
    }

    /// If the trip has begun (its start is in the past), the forecast starts now
    private static func forecastWindow(tripStart: Date) -> (start: Date, end: Date) {
        let start = max(tripStart, Date.now)
        return (start, start.advanced(by: forecastDays * SECONDS_IN_DAY))
    }
}
