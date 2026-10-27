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

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isMapLoading: Bool = true
    @State private var isShowingTitle: Bool = false

    var body: some View {
        heroBackground
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if isShowingTitle {
                    titleBlock
                        .transition(.opacity)
                }
            }
            .clipShape(.rect(cornerRadius: defaultCornerRadius))
            .onChange(of: trip.destination?.mapCameraPosition ?? TripLocation.sampleOrigin.mapCameraPosition, initial: true) {
                cameraPosition = trip.destination?.mapCameraPosition ?? TripLocation.sampleOrigin.mapCameraPosition
            }
            .onAppear {
                withAnimation(.easeIn(duration: 0.5)) {
                    isShowingTitle = true
                }
            }
    }

    @ViewBuilder
    private var heroBackground: some View {
        if let coverPhoto = trip.coverPhoto {
            Color(.systemGray5)
                .overlay {
                    CoverPhotoImageView(photo: coverPhoto)
                }
        } else if isMapLoading {
            // Skeleton view while map is loading
            Rectangle()
                .fill(Color(.systemGray5))
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, Color.primary.opacity(0.15), Color.clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .offset(x: isMapLoading ? 400 : -400)
                        .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: isMapLoading)
                )
                .task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.3)) {
                        isMapLoading = false
                    }
                }
        } else {
            Map(position: $cameraPosition)
                .transition(.opacity)
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

                departureInfo
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

    @ViewBuilder
    private var departureInfo: some View {
        let calendar = Calendar.current
        let now = Date.now
        let beginDateString = trip.startDate.formatted(date: .abbreviated, time: .omitted)
        let endDateString = trip.endDate.formatted(date: .abbreviated, time: .omitted)

        if calendar.isDateInToday(trip.startDate) {
            Label { Text("Departing today!") } icon: { trip.primaryType.startIcon }
        } else if now < trip.startDate {
            Label { Text("Departing on \(beginDateString)") } icon: { trip.primaryType.startIcon }
        } else if calendar.isDateInToday(trip.endDate) {
            Label { Text("Returning today") } icon: { trip.primaryType.endIcon }
        } else if now < trip.endDate {
            Label { Text("Returning on \(endDateString)") } icon: { trip.primaryType.endIcon }
        } else {
            Label { Text("Returned on \(endDateString)") } icon: { trip.primaryType.endIcon }
        }
    }
}

#Preview(traits: .sampleData) {
    @Previewable @Query var trips: [Trip]
    TripDetailHeroView(trip: trips.first!, tripWeather: nil)
        .frame(height: 380)
        .padding()
}
