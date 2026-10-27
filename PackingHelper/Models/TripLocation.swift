//
//  TripLocation.swift
//  PackingHelper
//
//  Created by Todd Louison on 10/13/23.
//

import Observation
import SwiftData
import SwiftUI
import MapKit
import WeatherKit
import OSLog

@Model
final class TripLocation: Equatable {
    var name: String = "Location"
    
    @Relationship(inverse: \Trip.origin) var originTrips: [Trip]? = []
    @Relationship(inverse: \Trip.destination) var destinationTrips: [Trip]? = []
    @Relationship(inverse: \User.defaultLocation) var usersWithDefault: [User]? = []

    var latitude: Double = 40.7128
    var longitude: Double = -74.0060
    
    var created: Date = Date.now
    
    @Transient var weather: TripWeather = TripWeather(currentWeather: nil, dailyForecast: nil)
    /// Trip dates `weather` was fetched for; other dates (or an edited trip) need a new fetch
    @Transient var weatherTripDates: DateInterval? = nil
    var weatherLastFetched: Date = Date.distantPast
    
    init(name: String, latitude: Double, longitude: Double) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
    
    // Equatable conformance
    static func == (lhs: TripLocation, rhs: TripLocation) -> Bool {
        lhs.id == rhs.id
    }
}

extension TripLocation {
    var location: CLLocation {
        CLLocation(latitude: self.latitude, longitude: self.longitude)
    }
    
    var coordinates: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: self.latitude, longitude: self.longitude)
    }
    
    var mapCameraPosition: MapCameraPosition {
        .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
    }

    /// City-level framing for trip cards, where street-level detail reads as noise on large cards
    var overviewCameraPosition: MapCameraPosition {
        .region(MKCoordinateRegion(
            center: coordinates,
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        ))
    }
}

extension TripLocation {
    func canGetCurrentWeather(for trip: Trip) -> Bool {
        return !trip.complete
    }
    
    func canGetWeatherForecast(for trip: Trip) -> Bool {
        return !trip.complete && trip.startDate <= Date().advanced(by: 5 * SECONDS_IN_DAY)
    }
    
    func getCurrentWeather(for trip: Trip) async -> CurrentWeather? {
        if self.canGetCurrentWeather(for: trip) {
            let weatherService = WeatherService()
            
            do {
                return try await weatherService.weather(for: self.location).currentWeather
            } catch {
                return nil
            }
        }
        return nil
    }
    
    private func getForecastStartAndEnd(trip: Trip) -> (start: Date, end: Date) {
        // If the trip has begin (i.e. the start date is in the past) we want
        // the start of the forecast to be the current date
        let startDate = max(trip.startDate, Date.now)
        let endDate = startDate.advanced(by: 5 * SECONDS_IN_DAY)
        return (startDate, endDate)
    }
    
    func getWeatherForecast(for trip: Trip) async -> Forecast<DayWeather>? {
        if canGetWeatherForecast(for: trip) {
            let weatherService = WeatherService()
            
            let (startDate, endDate) = self.getForecastStartAndEnd(trip: trip)
            
            do {
                return try await weatherService.weather(
                    for: self.location,
                    including: .daily(startDate: startDate, endDate: endDate)
                )
            } catch {
                return nil
            }
        }
        return nil
    }
    
    func getTripWeather(for trip: Trip) async -> TripWeather? {
        // Try to get cached weather first. We refetch every hour. `weather` is transient, so after a
        // relaunch it's empty even though `weatherLastFetched` persisted — only treat it as a hit if it has data.
        AppLogger.weather.debug("Checking weather cache. Last fetched: \(self.weatherLastFetched), \(self.weatherLastFetched.distance(to: .now)) seconds ago")
        let hasCachedWeather = weather.currentWeather != nil || weather.dailyForecast != nil
        let tripDates = DateInterval(start: trip.startDate, end: max(trip.startDate, trip.endDate))
        if hasCachedWeather && weatherTripDates == tripDates
            && weatherLastFetched.distance(to: .now) < SECONDS_IN_MINUTE * MINUTES_IN_HOUR {
            return self.weather
        }

        let weatherService = WeatherService()

        let allowCurrentWeather = canGetCurrentWeather(for: trip)
        let allowForecastWeather = canGetWeatherForecast(for: trip)

        let newWeather: TripWeather

        if allowCurrentWeather && allowForecastWeather {
            AppLogger.weather.debug("Fetching current weather + 5-day forecast")
            let (startDate, endDate) = self.getForecastStartAndEnd(trip: trip)

            do {
                let weatherData = try await weatherService.weather(
                    for: self.location,
                    including: .daily(startDate: startDate, endDate: endDate),
                    .current
                )
                newWeather = TripWeather(currentWeather: weatherData.1, dailyForecast: weatherData.0)
            } catch {
                // Don't stamp weatherLastFetched on failure, so the next appearance retries.
                AppLogger.weather.error("Failed to fetch weather: \(error.localizedDescription)")
                return nil
            }
        } else if allowCurrentWeather {
            AppLogger.weather.debug("Fetching current weather only")
            newWeather = await TripWeather(currentWeather: self.getCurrentWeather(for: trip), dailyForecast: nil)
        } else if allowForecastWeather {
            AppLogger.weather.debug("Fetching forecast weather only")
            newWeather = await TripWeather(currentWeather: nil, dailyForecast: self.getWeatherForecast(for: trip))
        } else {
            AppLogger.weather.debug("No weather data available for this trip")
            newWeather = TripWeather(currentWeather: nil, dailyForecast: nil)
        }

        // Mutate on MainActor
        await MainActor.run {
            self.weatherLastFetched = Date.now
            self.weatherTripDates = tripDates
            self.weather = newWeather
        }

        return self.weather
    }
}

extension TripLocation {
    static var sampleOrigin: TripLocation {
        TripLocation(name: "New York City", latitude: 40.7128, longitude: -74.0060)
    }
    
    static var sampleDestination: TripLocation {
        TripLocation(name: "Amsterdam", latitude: 52.3676, longitude: 4.9041)
    }
}
