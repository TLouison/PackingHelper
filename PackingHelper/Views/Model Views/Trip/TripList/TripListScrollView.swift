//
//  TripListScrollView.swift
//  PackingHelper
//
//  Created by Todd Louison on 10/17/23.
//

import SwiftUI
import SwiftData

struct TripListScrollView: View {
    //    @Environment(PurchaseManager.self) private var purchaseManager: PurchaseManager
    @Environment(\.modelContext) var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @Binding var path: NavigationPath
    
    @State private var tripToDelete: Trip? = nil
    @State private var showTripDeleteAlert: Bool = false
    @State private var reviewingTrip: Trip? = nil
    /// Landscape has no room for rows, so regular width switches to a full-height shelf
    @State private var isLandscape: Bool = false
    
    var trips: [Trip]
    /// Leads with the past trips summary card
    var showsPastTripsSummary: Bool = false
    /// Completed trips; when present, a trailing card opens them
    var pastTrips: [Trip] = []
    /// Changes to scroll back to the first card (upcoming trips are sorted soonest first)
    var scrollToStart: Int = 0

    @State private var scrollPosition = ScrollPosition()
    
    func deleteTrip() {
        if let trip = tripToDelete {
            modelContext.delete(trip)
        }
    }
    
    /// Share of the screen the featured card takes: height in portrait, width in landscape
    private static let featuredFraction: CGFloat = 0.6

    /// Upcoming trips lead with the next departure as a wide card on regular width
    private var featuredTrip: Trip? {
        showsPastTripsSummary ? nil : trips.first
    }

    var body: some View {
        Group {
            // Regular width (iPhone Duo unfolded, iPad): a vertical grid instead of one full-screen card per page
            if horizontalSizeClass == .regular {
                if isLandscape {
                    shelfLayout
                } else {
                    gridLayout
                }
            } else {
                pagerLayout
            }
        }
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.size.width > proxy.size.height
        } action: { isLandscape in
            self.isLandscape = isLandscape
        }
        .onChange(of: scrollToStart) {
            // The grid scrolls vertically; the pager and shelf scroll sideways
            let edge: Edge = horizontalSizeClass == .regular && !isLandscape ? .top : .leading
            withAnimation(.smooth) {
                scrollPosition.scrollTo(edge: edge)
            }
        }
        // Presented from outside the scroll content so the summary card doesn't own the sheet
        .sheet(item: $reviewingTrip) { trip in
            TemplateUpdateSheet(trip: trip) {
                trip.templateReviewDismissed = true
            }
        }
        .alert("Delete Trip", isPresented: $showTripDeleteAlert) {
            Button("Cancel", role: .cancel) {
                tripToDelete = nil
            }
            Button("Delete", role: .destructive) {
                deleteTrip()
            }
        } message: {
            Text("Are you sure you want to delete this trip? This cannot be undone.")
        }
    }
}

extension TripListScrollView {
    private var summaryCard: some View {
        PastTripsSummaryCard(path: $path, trips: trips) { trip in
            reviewingTrip = trip
        }
    }

    private var entryCard: some View {
        PastTripsEntryCard(trips: pastTrips) {
            path.append(TripListRoute.pastTrips)
        }
    }

    private var pagerLayout: some View {
        ScrollView(.horizontal) {
            HStack {
                if showsPastTripsSummary {
                    summaryCard
                        .modifier(TripCardPageStyle())
                }

                ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                    tripCard(trip, index: index)
                        .modifier(TripCardPageStyle())
                }

                if !pastTrips.isEmpty {
                    entryCard
                        .modifier(TripCardPageStyle())
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 24, for: .scrollContent)
        .scrollTargetBehavior(.paging)
        .scrollPosition($scrollPosition)
    }

    private var gridLayout: some View {
        let featured = featuredTrip
        let gridTrips = Array(trips.enumerated().dropFirst(featured == nil ? 0 : 1))

        return ScrollView {
            VStack(spacing: 16) {
                if let featured {
                    tripCard(featured, index: 0, isFeatured: true)
                        .containerRelativeFrame(.vertical) { length, _ in
                            length * Self.featuredFraction
                        }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                    if showsPastTripsSummary {
                        summaryCard
                            .aspectRatio(3 / 4, contentMode: .fit)
                    }

                    ForEach(gridTrips, id: \.element.id) { index, trip in
                        tripCard(trip, index: index)
                            .aspectRatio(3 / 4, contentMode: .fit)
                    }

                    if !pastTrips.isEmpty {
                        entryCard
                            .aspectRatio(3 / 4, contentMode: .fit)
                    }
                }
            }
            .padding(.vertical)
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollPosition($scrollPosition)
    }

    /// Landscape: one row of tall cards, each the full height of the screen, scrolling sideways
    private var shelfLayout: some View {
        let featured = featuredTrip

        return ScrollView(.horizontal) {
            LazyHStack(spacing: 16) {
                if showsPastTripsSummary {
                    summaryCard
                        .modifier(TripCardShelfStyle())
                }

                ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                    if trip == featured {
                        tripCard(trip, index: index, isFeatured: true)
                            .containerRelativeFrame(.horizontal) { length, _ in
                                length * Self.featuredFraction
                            }
                            .containerRelativeFrame(.vertical)
                    } else {
                        tripCard(trip, index: index)
                            .modifier(TripCardShelfStyle())
                    }
                }

                if !pastTrips.isEmpty {
                    entryCard
                        .modifier(TripCardShelfStyle())
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(16, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollPosition($scrollPosition)
    }

    private func tripCard(_ trip: Trip, index: Int, isFeatured: Bool = false) -> some View {
        // Use ZStack to guarantee a hittable layer
        ZStack {
            TripListRowView(trip: trip, isFeatured: isFeatured)
                // Display only; the layer below takes taps. Keeps row content that draws past the
                // card's edges from swallowing taps meant for neighboring cards.
                .allowsHitTesting(false)

            Color.clear
                .contentShape(RoundedRectangle(cornerRadius: defaultCornerRadius))
                .onTapGesture {
                    path.append(trip)
                }
        }
        // The tap layer isn't a Button, so expose the card to VoiceOver as one
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            path.append(trip)
        }
        .accessibilityAction(named: "Delete") {
            tripToDelete = trip
            showTripDeleteAlert.toggle()
        }
        .contextMenu {
            Button(role: .destructive) {
                tripToDelete = trip
                showTripDeleteAlert.toggle()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } preview: {
            TripListRowView(trip: trip)
                .frame(width: 300, height: 440)
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 10))
        }
    }
}

/// Sizes a card to the full height of the landscape shelf, in the same tall shape as the grid
private struct TripCardShelfStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .aspectRatio(3 / 4, contentMode: .fit)
            .containerRelativeFrame(.vertical)
    }
}

/// Sizes a card to one page of the trip pager
private struct TripCardPageStyle: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .padding(.vertical)
            .containerRelativeFrame(.horizontal, count: 1, spacing: 16)
            .scrollTransition { content, phase in
                content
                    .opacity(phase.isIdentity ? 1.0 : 0.8)
                    // Reduce Motion keeps the fade but drops the squash
                    .scaleEffect(y: phase.isIdentity || reduceMotion ? 1.0 : 0.9)
            }
    }
}

//#Preview {
//    TripListScrollView()
//}

