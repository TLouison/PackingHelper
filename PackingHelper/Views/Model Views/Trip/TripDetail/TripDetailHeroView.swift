//
//  TripDetailHeader.swift
//  PackingHelper
//
//  Created by Todd Louison on 10/18/23.
//

import SwiftUI
import MapKit
import WeatherKit

struct TripDetailHeroView: View {
    @Bindable var trip: Trip
    @Binding var tripWeather: TripWeather?

    @Binding var isShowingTripSettingsSheet: Bool

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isMapLoading: Bool = true

    var body: some View {
        ZStack {
            if trip.coverPhoto != nil {
                // Cover photo is drawn as the background below.
            } else if isMapLoading {
                // Skeleton view while map is loading
                RoundedRectangle(cornerRadius: defaultCornerRadius)
                    .fill(Color(.systemGray5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: defaultCornerRadius)
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
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                isMapLoading = false
                            }
                        }
                    }
            } else {
                Map(position: $cameraPosition)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(.rect(cornerRadius: defaultCornerRadius))
                    .transition(.opacity)
            }
            
            TripDetailOverlay(trip: trip, tripWeather: $tripWeather, isShowingTripSettingsSheet: $isShowingTripSettingsSheet)
                .transition(
                    .asymmetric(
                        insertion: .opacity.animation(.bouncy),
                        removal: .opacity.animation(.easeOut)
                    )
                )
                .onChange(of: trip.destination?.mapCameraPosition ?? TripLocation.sampleOrigin.mapCameraPosition,  initial: true) {
                    cameraPosition = trip.destination?.mapCameraPosition ?? TripLocation.sampleOrigin.mapCameraPosition
                }
                .frame(minHeight: 400)
                .padding(.bottom, 8)
                .padding(.horizontal, 8)
        }
        .background {
            if let coverPhoto = trip.coverPhoto {
                CoverPhotoImageView(photo: coverPhoto)
                    .clipShape(.rect(cornerRadius: defaultCornerRadius))
            }
        }
    }
}
//
//#Preview {
//    TripDetailHeader()
//}
