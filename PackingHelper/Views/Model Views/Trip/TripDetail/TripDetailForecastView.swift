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

    /// Whether the section draws anything (a forecast or the pending card), so layouts can
    /// give its space to a neighbor when it doesn't
    static func isShown(for trip: Trip, weather: TripWeather?) -> Bool {
        weather?.dailyForecast != nil || forecastOpensDate(for: trip) != nil
    }

    var body: some View {
        Group {
            if let forecast {
                TripDetailSectionView(title: "Forecast") {
                    Grid {
                        // Weekday on the first day only; the rest follow from it
                        GridRow {
                            Text("")
                            Text("")
                            ForEach(Array(forecast.enumerated()), id: \.element.date) { index, weather in
                                Text(index == 0 ? weather.date.formatted(.dateTime.weekday(.abbreviated)) : "")
                                    .font(.caption2.weight(.semibold))
                                    .textCase(.uppercase)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        GridRow {
                            Text("\(trip.startDate.formatted(.dateTime.month()))")
                            Text("") // Hack because EmptyView does not work in cells
                            ForEach(forecast, id: \.date) { weather in
                                Text ("\(weather.date.formatted(.dateTime.day()))")
                                    .padding(.bottom, 5)
                            }
                        }
                        .font(.headline)
                        .fontWeight(.semibold)
                        .gridCellAnchor(.top)
                        
                        GridRow {
                            Text("")
                            Text("")
                            
                            ForEach(forecast, id: \.date) { weather in
                                Image(systemName: weather.symbolName)
                                    .font(.title)
                                    .symbolVariant(.fill)
                                    .symbolRenderingMode(colorScheme == .dark ? .multicolor : .palette)
                            }
                        }
                        .padding(.bottom, 10)
                        
                        GridRow {
                            Text("High (\(temperatureUnit.symbol))").font(.caption)
                            Text("")
                            ForEach(forecast, id: \.date) { weather in
                                Text("\(weather.highTemperature.converted(to: temperatureUnit).value.formatted(.number.precision(.fractionLength(.zero))))")
                            }
                        }
                        
                        GridRow {
                            Text("")
                            Text("")
                            ForEach(forecast, id: \.date) { weather in
                                Divider().frame(maxWidth: 30)
                            }
                        }
                        
                        GridRow {
                            Text("Low (\(temperatureUnit.symbol))").font(.caption)
                            Text("")
                            ForEach(forecast, id: \.date) { weather in
                                Text("\(weather.lowTemperature.converted(to: temperatureUnit).value.formatted(.number.precision(.fractionLength(.zero))))")
                                
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .transition(.move(edge: .bottom))
            } else if let forecastOpensDate {
                TripDetailSectionView(title: "Forecast") {
                    pendingForecast(opens: forecastOpensDate)
                }
            }
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
