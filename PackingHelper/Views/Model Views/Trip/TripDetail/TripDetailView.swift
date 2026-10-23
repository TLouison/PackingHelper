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
    @State private var isShowingTripSettingsSheet: Bool = false
    
    @State private var isAddingNewPackingList: Bool = false
    @State private var isApplyingDefaultPackingList: Bool = false
    
    @State private var tripWeather: TripWeather?

    /// Compact only: the inline nav title fades in once the hero's title has scrolled away
    @State private var isShowingNavigationTitle: Bool = false
    /// iPhone Duo folded: toolbar becomes a sidebar, and Edit moves into it
    @State private var isShowingVerticalToolbar: Bool = false

    /// Compact hero takes 45% of the visible height, so short windows (Duo outer display) keep room for content
    private static func heroHeight(forContainerHeight containerHeight: CGFloat) -> CGFloat {
        min(max(containerHeight * 0.45, 240), 380)
    }
    @State private var compactHeroHeight: CGFloat = 380
    
    var body: some View {
        content
            .navigationTitle(trip.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Sidebar mode has no horizontal bar to show a title in; a principal item would keep an empty one around
                if !isShowingVerticalToolbar {
                    ToolbarItem(placement: .principal) {
                        Text(trip.name)
                            .font(.headline)
                            .opacity(isShowingNavigationTitle ? 1 : 0)
                            .animation(.easeInOut(duration: 0.2), value: isShowingNavigationTitle)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }

                ToolbarItem(placement: isShowingVerticalToolbar ? .bottomBar : .topBarTrailing) {
                    Button("Edit Trip", systemImage: "pencil") {
                        isShowingTripSettingsSheet = true
                    }
                }
            }
            // Sidebar mode still reserves a horizontal title strip; drop the title so it has nothing to show
            .toolbar(removing: isShowingVerticalToolbar ? .title : nil)
            .readsVerticalToolbar($isShowingVerticalToolbar)
            .sheet(isPresented: $isShowingTripSettingsSheet) { TripEditView(trip: trip, isDeleted: $isDeleted) }
            .sheet(isPresented: $isAddingNewPackingList) {
                PackingListEditView(trip: trip, isDeleted: .constant(false))
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $isApplyingDefaultPackingList) {
                PackingListApplyDefaultView(trip: trip)
            }
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
            // Regular width (iPhone Duo unfolded, iPad) fits on one screen when it can
            GeometryReader { geometry in
                if geometry.size.width > geometry.size.height {
                    landscapeLayout
                } else {
                    // Scrolls only when the cards don't fit, e.g. large Dynamic Type or a short window
                    ViewThatFits(in: .vertical) {
                        portraitLayout

                        ScrollView {
                            portraitLayout
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 20) {
                    heroView
                        .containerRelativeFrame(.vertical) { length, _ in
                            Self.heroHeight(forContainerHeight: length)
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { compactHeroHeight = $0 }
                    packingSection
                    forecastSection
                    infoSection
                    photoCredit
                }
                .padding()
            }
            // With the toolbar in the sidebar the top edge is free, so start content there instead of under an empty bar
            .ignoresSafeArea(.container, edges: isShowingVerticalToolbar ? .top : [])
            .onScrollGeometryChange(for: Bool.self) { geometry in
                // Title block sits at the bottom of the hero
                geometry.contentOffset.y + geometry.contentInsets.top > compactHeroHeight - 40
            } action: { _, isPastHero in
                isShowingNavigationTitle = isPastHero
            }
        }
    }

    /// Hero pinned on the left; the packing card takes whatever height the right column has left
    private var landscapeLayout: some View {
        HStack(alignment: .top, spacing: 20) {
            heroView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Fixed column when the cards fit; scrolls (without stretching) only on unusually short windows
            ViewThatFits(in: .vertical) {
                landscapeColumn
                    .environment(\.tripDetailCardFillsHeight, true)
                    .frame(maxHeight: .infinity, alignment: .top)

                ScrollView {
                    landscapeColumn
                }
                .scrollIndicators(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding()
    }

    private var landscapeColumn: some View {
        VStack(spacing: 20) {
            packingSection
            forecastSection
            infoSection
            photoCredit
        }
    }

    /// Wide hero on top, packing and info side by side (equal height) underneath
    private var portraitLayout: some View {
        VStack(spacing: 20) {
            heroView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 240)

            forecastSection

            HStack(alignment: .top, spacing: 20) {
                packingSection
                    .frame(maxWidth: .infinity)
                infoSection
                    .frame(maxWidth: .infinity)
            }
            .environment(\.tripDetailCardFillsHeight, true)
            .fixedSize(horizontal: false, vertical: true)

            photoCredit
        }
        .padding()
    }

    private var heroView: some View {
        TripDetailHeroView(trip: trip, tripWeather: tripWeather)
            .shaded()
    }

    private var packingSection: some View {
        TripDetailPackingView(
            trip: trip,
            isAddingNewPackingList: $isAddingNewPackingList,
            isApplyingDefaultPackingList: $isApplyingDefaultPackingList
        )
    }

    private var forecastSection: some View {
        TripDetailForecastView(trip: trip, tripWeather: $tripWeather)
            .shadow(radius: defaultShadowRadius)
    }

    private var infoSection: some View {
        TripDetailInfoView(trip: trip)
            .shadow(radius: defaultShadowRadius)
    }

    @ViewBuilder
    private var photoCredit: some View {
        if let coverPhoto = trip.coverPhoto, coverPhoto.source == .unsplash {
            TripDetailPhotoCreditView(photo: coverPhoto)
                .padding(.top, -8)
        }
    }
}
