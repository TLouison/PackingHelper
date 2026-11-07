//
//  TripDetailForecastView.swift
//  PackingHelper
//
//  Created by Todd Louison on 5/28/24.
//

import SwiftUI
import WeatherKit

struct TripDetailForecastView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    let trip: Trip
    @Binding var tripWeather: TripWeather?
    /// The trip's weather fetch hasn't finished yet
    var isLoading: Bool = false
    @State private var temperatureUnit: UnitTemperature = .fahrenheit
    
    var forecast: Forecast<DayWeather>? {
        if let tripWeather = tripWeather {
            return tripWeather.dailyForecast
        }
        return nil
    }
    
    /// Forecasts are only fetched this close to departure (`TripLocation.canGetWeatherForecast`)
    private static let forecastLeadDays = 5

    /// When the forecast becomes available, if the trip is still too far out for one
    private var forecastOpensDate: Date? {
        forecast == nil ? Self.forecastOpensDate(for: trip) : nil
    }

    private static func forecastOpensDate(for trip: Trip) -> Date? {
        guard !trip.complete, trip.destination != nil,
              let opens = Calendar.current.date(byAdding: .day, value: -forecastLeadDays, to: trip.startDate),
              opens > .now
        else { return nil }
        return opens
    }

    /// A forecast is on its way, so the section holds its place with a skeleton
    private var isAwaitingForecast: Bool {
        Self.isAwaitingForecast(for: trip, weather: tripWeather, isLoading: isLoading)
    }

    private static func isAwaitingForecast(for trip: Trip, weather: TripWeather?, isLoading: Bool) -> Bool {
        isLoading && weather?.dailyForecast == nil
            && trip.destination?.canGetWeatherForecast(for: trip) == true
    }

    /// Whether the section draws anything (a forecast, its loading skeleton, or the pending card),
    /// so layouts can give its space to a neighbor when it doesn't
    static func isShown(for trip: Trip, weather: TripWeather?, isLoading: Bool) -> Bool {
        weather?.dailyForecast != nil
            || isAwaitingForecast(for: trip, weather: weather, isLoading: isLoading)
            || forecastOpensDate(for: trip) != nil
    }

    var body: some View {
        if forecast != nil || isAwaitingForecast {
            TripDetailSectionView(title: "Forecast") {
                if let forecast {
                    forecastGrid(days: forecast.map(ForecastDay.init))
                        .transition(.opacity)
                } else {
                    // Same rows as the real forecast, so it fades in without moving the cards below
                    forecastGrid(days: placeholderDays)
                        .redacted(reason: .placeholder)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Loading forecast")
                        .transition(.opacity)
                }
            }
        } else if let forecastOpensDate {
            TripDetailSectionView(title: "Forecast") {
                pendingForecast(opens: forecastOpensDate)
            }
        }
    }

    private func forecastGrid(days: [ForecastDay]) -> some View {
        Grid {
            // Weekday on the first day only; the rest follow from it
            GridRow {
                Text("")
                Text("")
                ForEach(Array(days.enumerated()), id: \.element.date) { index, day in
                    Text(index == 0 ? day.date.formatted(.dateTime.weekday(.abbreviated)) : "")
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
            }

            GridRow {
                Text("\(trip.startDate.formatted(.dateTime.month()))")
                Text("") // Hack because EmptyView does not work in cells
                ForEach(days, id: \.date) { day in
                    Text ("\(day.date.formatted(.dateTime.day()))")
                        .padding(.bottom, 5)
                }
            }
            .font(.headline)
            .fontWeight(.semibold)
            .gridCellAnchor(.top)

            GridRow {
                Text("")
                Text("")

                ForEach(days, id: \.date) { day in
                    Image(systemName: day.symbolName)
                        .font(.title)
                        .symbolVariant(.fill)
                        .symbolRenderingMode(colorScheme == .dark ? .multicolor : .palette)
                }
            }
            .padding(.bottom, 10)

            GridRow {
                Text("High (\(temperatureUnit.symbol))").font(.caption)
                Text("")
                ForEach(days, id: \.date) { day in
                    Text(formatted(day.high))
                }
            }

            GridRow {
                Text("")
                Text("")
                ForEach(days, id: \.date) { _ in
                    Divider().frame(maxWidth: 30)
                }
            }

            GridRow {
                Text("Low (\(temperatureUnit.symbol))").font(.caption)
                Text("")
                ForEach(days, id: \.date) { day in
                    Text(formatted(day.low))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func formatted(_ temperature: Measurement<UnitTemperature>) -> String {
        temperature.converted(to: temperatureUnit).value.formatted(.number.precision(.fractionLength(.zero)))
    }

    /// Stand-in days for the loading skeleton; the forecast window is always this long
    private var placeholderDays: [ForecastDay] {
        (0..<Self.forecastLeadDays).map { offset in
            ForecastDay(
                date: Calendar.current.date(byAdding: .day, value: offset, to: trip.startDate) ?? trip.startDate,
                symbolName: "cloud.sun",
                high: Measurement(value: 70, unit: .fahrenheit),
                low: Measurement(value: 50, unit: .fahrenheit)
            )
        }
    }

    /// Too far out for a forecast: say when it will show instead of hiding the section
    private func pendingForecast(opens: Date) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "calendar.badge.clock")
                .font(.title)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Forecast opens \(opens.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.headline)
                Text("Weather shows up \(Self.forecastLeadDays) days before you leave for \(trip.destination?.name ?? "your trip").")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One forecast column, from WeatherKit or the loading skeleton
private struct ForecastDay {
    let date: Date
    let symbolName: String
    let high: Measurement<UnitTemperature>
    let low: Measurement<UnitTemperature>
}

extension ForecastDay {
    init(_ weather: DayWeather) {
        self.init(
            date: weather.date,
            symbolName: weather.symbolName,
            high: weather.highTemperature,
            low: weather.lowTemperature
        )
    }
}
