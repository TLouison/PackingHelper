//
//  TripListRowView.swift
//  PackingHelper
//
//  Created by Todd Louison on 10/13/23.
//

import SwiftUI
import SwiftData
import MapKit

struct TripListRowView: View {
    @Environment(\.modelContext) var modelContext

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var showDeleteTripAlert: Bool = false
    @State private var isMapLoading: Bool = true
    @State private var featureFlags = FeatureFlags.shared

    @Bindable var trip: Trip

    var disabled: Bool
 
    @ViewBuilder private func dateInfo() -> some View {
        trip.getStatusLabel()
            .font(.caption)
            .transition(
                .symbolEffect(.disappear)
                .combined(with: .push(from: .bottom))
                .animation(.easeInOut)
            )
        
        
        if trip.status == .upcoming || trip.status == .departing {
            Text(trip.startDate.formatted(date: .abbreviated, time: .omitted))
        }
        else if trip.status == .returning || trip.status == .complete {
            Text(trip.endDate.formatted(date: .abbreviated, time: .omitted))
        }
    }
    
    @ViewBuilder func tripRowOverlay(_ trip: Trip) -> some View {
            VStack {
                HStack(alignment: .top) {
                    if featureFlags.showingMultiplePackers {
                        UserIndicators(users: trip.packers)
                        .padding(.leading)
                    }
                    Spacer()
                    Text(trip.name)
                        .font(.title)
                        .roundedBox()
                        .shaded()
                }
                Spacer()
                HStack {
                    Spacer()
                    VStack(alignment: .trailing) {
                        dateInfo()
                    }
                    .font(.headline)
                    .roundedBox()
                    .shaded()
                }
            }
    }
    
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
            } else {
                Map(
                    position: $mapPosition,
                    interactionModes: []
                )
                .id(trip.destination?.id)
                .overlay(Color.clear.allowsHitTesting(true))
                .transition(.opacity)
            }

            tripRowOverlay(trip)
                .frame(maxWidth: .infinity)
                .padding()
            
            
            // Block the trip from being accessed if the user has more than the free amount
            if disabled {
                Color.black.opacity(0.8).frame(maxWidth: .infinity, maxHeight: .infinity)
                
                VStack(spacing: 32) {
                    VStack {
                        Text("This Trip is Disabled").font(.title)
                        Text("You may only plan up to \(Trip.maxFreeTrips) trips.").font(.subheadline)
                    }
                    
                    VStack {
                        Text("To regain access, please:")
                            .font(.headline)
                        VStack {
                            Text("- Complete your other trips.")
                            Text("- Remove other upcoming trips.")
                            plusSubscriptionWithText(before: "- Subscribe to")
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if let coverPhoto = trip.coverPhoto {
                CoverPhotoImageView(photo: coverPhoto)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: defaultCornerRadius))
        .shadow(radius: defaultShadowRadius)
        .onAppear {
            if let destination = trip.destination {
                mapPosition = destination.mapCameraPosition
            }
            // Simulate map loading delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.3)) {
                    isMapLoading = false
                }
            }
        }
        .onChange(of: trip.destination) { _, newDestination in
            if let destination = newDestination {
                mapPosition = destination.mapCameraPosition
            }
        }
    }
}

struct UserIndicators: View {
    let users: [User]
    
    var body: some View {
        HStack {
            ForEach(users.sorted()) { user in
                user.pillFirstInitialIconSolid
            }
        }
        .scaleEffect(1.4, anchor: .top)
    }
}

//#Preview {
//    TripListRowView()
//}

