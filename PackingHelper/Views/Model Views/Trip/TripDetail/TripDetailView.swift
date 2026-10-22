//
//  TripDetailView.swift
//  PackingHelper
//
//  Created by Todd Louison on 10/9/23.
//

import SwiftUI
import MapKit
import WeatherKit

struct RoundedModifier: ViewModifier {
    let corner: CGFloat
    
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .padding()
            .clipShape(RoundedRectangle(cornerRadius: corner))
    }
}

struct SheetModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .presentationDetents([.height(500), .large])
            .presentationDragIndicator(.automatic)
    }
}

struct TripDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    let trip: Trip
    
    @State private var isDeleted: Bool = false
    @State private var isShowingTripDetailSheet: Bool = false
    @State private var isShowingTripSettingsSheet: Bool = false
    
    @State private var isAddingNewPackingList: Bool = false
    @State private var isApplyingDefaultPackingList: Bool = false
    
    @GestureState private var isDetectingLongPress = false
    @State private var completedLongPress = false
    @State private var isShowingTapAnywherePrompt = false
    
    @State private var tripWeather: TripWeather?
    
    var body: some View {
        content
            .sheet(isPresented: $isShowingTripDetailSheet) { TripDetailSheet(trip: trip) }
            .sheet(isPresented: $isShowingTripSettingsSheet) { TripEditView(trip: trip, isDeleted: $isDeleted) }
            .sheet(isPresented: $isAddingNewPackingList) {
                PackingListEditView(trip: trip, isDeleted: .constant(false))
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $isApplyingDefaultPackingList) {
                PackingListApplyDefaultView(trip: trip)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                tripWeather = await trip.destination?.getTripWeather(for: trip)
            }
            .onChange(of: isDeleted) {
                if isDeleted {
                    dismiss()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if horizontalSizeClass == .regular {
            // Regular width (iPhone Duo unfolded, iPad): hero fills the left half, info boxes scroll on the right
            HStack(spacing: 0) {
                heroView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()

                ScrollView {
                    VStack(spacing: 20) {
                        infoSections
                    }
                    .padding()
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 20) {
                    heroView
                    infoSections
                }
                .padding()
            }
        }
    }

    private var heroView: some View {
        TripDetailHeroView(
            trip: trip,
            tripWeather: $tripWeather,
            isShowingTripSettingsSheet: $isShowingTripSettingsSheet
        )
            .shadow(radius: defaultShadowRadius)
    }

    @ViewBuilder
    private var infoSections: some View {
        TripDetailPackingView(
            trip: trip,
            isAddingNewPackingList: $isAddingNewPackingList,
            isApplyingDefaultPackingList: $isApplyingDefaultPackingList
        )
            .shadow(radius: defaultShadowRadius)

        TripDetailForecastView(trip: trip, tripWeather: $tripWeather)
            .shadow(radius: defaultShadowRadius)

        TripDetailInfoView(trip: trip)
            .shadow(radius: defaultShadowRadius)

        if let coverPhoto = trip.coverPhoto, coverPhoto.source == .unsplash {
            TripDetailPhotoCreditView(photo: coverPhoto)
                .padding(.top, -8)
        }
    }
}
