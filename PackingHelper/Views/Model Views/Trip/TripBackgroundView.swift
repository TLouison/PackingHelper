//
//  TripBackgroundView.swift
//  PackingHelper
//
//  The cover photo or destination map behind a trip, shared by the trip list
//  card and the trip detail hero. Fills whatever frame it's given.
//

import SwiftUI
import MapKit

struct TripBackgroundView: View {
    enum Style {
        /// Trip list card: city-level muted map that doesn't move
        case card
        /// Detail hero: street-level interactive map
        case hero
    }

    let trip: Trip
    let style: Style

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isMapLoading: Bool = true
    @State private var isShimmering: Bool = false

    /// Where the map should look; nil leaves the card's map where it is
    private var targetPosition: MapCameraPosition? {
        switch style {
        case .card:
            trip.destination?.overviewCameraPosition
        case .hero:
            (trip.destination ?? TripLocation.sampleOrigin).mapCameraPosition
        }
    }

    var body: some View {
        content
            .onChange(of: targetPosition, initial: true) {
                if let targetPosition {
                    cameraPosition = targetPosition
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let coverPhoto = trip.coverPhoto {
            switch style {
            case .card:
                CoverPhotoImageView(photo: coverPhoto)
            case .hero:
                Color(.systemGray5)
                    .overlay {
                        CoverPhotoImageView(photo: coverPhoto)
                    }
            }
        } else if isMapLoading {
            skeleton
        } else {
            map
        }
    }

    /// Placeholder while the map is loading
    private var skeleton: some View {
        // The hero's sweep is keyed to isMapLoading, which is always true here, so it stays parked
        let sweeping = style == .card ? isShimmering : isMapLoading
        return Rectangle()
            .fill(Color(.systemGray5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.clear, Color.primary.opacity(0.15), Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: sweeping ? 400 : -400)
                    // Scoped to the gradient: a withAnimation forever transaction also catches the
                    // overlay's glass boxes sizing in on first layout, looping them small → full
                    .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: sweeping)
            )
            // The shimmer sweeps past the card's edges; clipping doesn't limit hit testing
            .allowsHitTesting(false)
            .onAppear {
                // Started by the skeleton itself, not keyed to isMapLoading: a forever animation on the
                // change that removes the skeleton keeps it alive (invisible, sweeping over neighboring cards)
                if style == .card {
                    isShimmering = true
                }
            }
            .task {
                // Simulate map loading delay
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    isMapLoading = false
                }
            }
    }

    @ViewBuilder
    private var map: some View {
        switch style {
        case .card:
            Map(
                position: $cameraPosition,
                interactionModes: []
            )
            // Points of interest turn the card into a street map; muted keeps the info bar readable
            .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
            .id(trip.destination?.id)
            .overlay(Color.clear.allowsHitTesting(true))
            .transition(.opacity)
        case .hero:
            Map(position: $cameraPosition)
                .transition(.opacity)
        }
    }
}
