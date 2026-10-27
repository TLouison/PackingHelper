//
//  TripDetailHeader.swift
//  PackingHelper
//
//  Created by Todd Louison on 10/18/23.
//

import SwiftUI
import SwiftData
import MapKit
import WeatherKit

struct TripDetailHeroView: View {
    @Bindable var trip: Trip
    let tripWeather: TripWeather?

    @State private var isShowingTitle: Bool = false

    var body: some View {
        TripBackgroundView(trip: trip, style: .hero)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if isShowingTitle {
                    titleBlock
                        .transition(.opacity)
                }
            }
            .clipShape(.rect(cornerRadius: defaultCornerRadius))
            .onAppear {
                withAnimation(.easeIn(duration: 0.5)) {
                    isShowingTitle = true
                }
            }
    }

    private var titleBlock: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.name)
                    .font(.largeTitle.bold())
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                // Skip the destination when the trip is just named after it ("Tokyo / Tokyo")
                if let destination = trip.destination, destination.name != trip.name {
                    Text(destination.name)
                        .font(.headline)
                }

                trip.statusDateText
                    .font(.subheadline)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 4, y: 1)

            Spacer(minLength: 12)

            if let currentWeather = tripWeather?.currentWeather {
                WeatherChip(weather: currentWeather)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottom) {
            // Scrim reaches above the text so it fades out instead of ending in a hard edge
            LinearGradient(
                colors: [.clear, .black.opacity(0.35), .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.top, -80)
            .allowsHitTesting(false)
        }
    }

}

#Preview(traits: .sampleData) {
    @Previewable @Query var trips: [Trip]
    TripDetailHeroView(trip: trips.first!, tripWeather: nil)
        .frame(height: 380)
        .padding()
}
