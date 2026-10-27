//
//  TripBackgroundView.swift
//  PackingHelper
//
//  The cover photo or destination map behind a trip, shared by the trip list
//  card and the trip detail hero. Fills whatever frame it's given. The card
//  shows a cached map snapshot; the hero keeps a live, interactive map.
//

import SwiftUI
import MapKit

struct TripBackgroundView: View {
    enum Style {
        /// Trip list card: city-level muted map snapshot
        case card
        /// Detail hero: street-level interactive map
        case hero
    }

    let trip: Trip
    let style: Style

    // Hero
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isMapLoading: Bool = true

    // Card
    @State private var isShimmering: Bool = false
    @State private var snapshot: UIImage?
    @State private var cardSize: CGSize = .zero

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        content
            .onChange(of: heroPosition, initial: true) {
                if let heroPosition {
                    cameraPosition = heroPosition
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
        } else if style == .card {
            cardMap
        } else if isMapLoading {
            skeleton
                .task {
                    // Simulate map loading delay
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
                // Started by the skeleton itself, not keyed to the loading state: a forever animation on the
                // change that removes the skeleton keeps it alive (invisible, sweeping over neighboring cards)
                if style == .card {
                    isShimmering = true
                }
            }
    }

    // MARK: - Hero map

    /// Where the hero's map looks
    private var heroPosition: MapCameraPosition? {
        guard style == .hero else { return nil }
        return (trip.destination ?? TripLocation.sampleOrigin).mapCameraPosition
    }

    // MARK: - Card map

    /// Used when the trip has no destination: a wide view of the world
    private static let worldRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 180)
    )

    private var snapshotRequest: MapSnapshotRequest? {
        let region = trip.destination?.overviewCameraPosition.region ?? Self.worldRegion
        return MapSnapshotRequest(
            center: region.center,
            span: region.span,
            size: cardSize,
            displayScale: displayScale,
            isDark: colorScheme == .dark
        )
    }

    private var cardMap: some View {
        let request = snapshotRequest
        // A cache hit shows on the first render, with no skeleton flash when a card scrolls back in
        let image = request.flatMap { MapSnapshotLoader.shared.cachedImage(for: $0) } ?? snapshot

        return ZStack {
            if let image {
                Color.clear
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                    .transition(.opacity)
            } else {
                skeleton
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { cardSize = $0 }
        .task(id: request) {
            guard let request else { return }
            if let loaded = await MapSnapshotLoader.shared.image(for: request), !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.3)) {
                    snapshot = loaded
                }
            }
        }
    }
}
