//
//  WeatherChip.swift
//  PackingHelper
//
//  Created by Todd Louison on 9/16/25.
//
//  The destination's weather right now, shown on the trip hero. Labeled "Now" so it
//  isn't read as the trip's forecast (that lives in the Forecast section).
//

import SwiftUI
import WeatherKit

struct WeatherChip: View {
    let weather: CurrentWeather

    /// Narrow width ("54°") to keep the chip small; the unit follows the locale
    private var temperature: String {
        weather.temperature.formatted(
            .measurement(width: .narrow, numberFormatStyle: .number.precision(.fractionLength(0)))
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Now")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .opacity(0.8)

            HStack(spacing: 6) {
                Image(systemName: weather.symbolName)
                Text(temperature)
                    .monospacedDigit()
            }
            .font(.headline)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weather there now")
        .accessibilityValue("\(weather.condition.description), \(temperature)")
    }
}
