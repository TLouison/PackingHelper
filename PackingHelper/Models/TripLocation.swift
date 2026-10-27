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

/// Weather reads `Trip` / `TripLocation` state, so these run on the main actor. Inputs are copied
/// into plain values before the hop to `WeatherProvider`, which owns the service and the cache.
@MainActor
extension TripLocation {
    func canGetCurrentWeather(for trip: Trip) -> Bool {
        return !trip.complete
    }

    func canGetWeatherForecast(for trip: Trip) -> Bool {
        return !trip.complete && trip.startDate <= Date().advanced(by: 5 * SECONDS_IN_DAY)
    }

    func getCurrentWeather(for trip: Trip) async -> CurrentWeather? {
        guard canGetCurrentWeather(for: trip) else { return nil }
        return await WeatherProvider.shared.currentWeather(latitude: latitude, longitude: longitude)
    }

    func getWeatherForecast(for trip: Trip) async -> Forecast<DayWeather>? {
        guard canGetWeatherForecast(for: trip) else { return nil }
        return await WeatherProvider.shared.forecast(latitude: latitude, longitude: longitude, tripStart: trip.startDate)
    }

    func getTripWeather(for trip: Trip) async -> TripWeather? {
        await WeatherProvider.shared.tripWeather(
            latitude: latitude,
            longitude: longitude,
            tripStart: trip.startDate,
            tripEnd: trip.endDate,
            allowCurrent: canGetCurrentWeather(for: trip),
            allowForecast: canGetWeatherForecast(for: trip)
        )
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
