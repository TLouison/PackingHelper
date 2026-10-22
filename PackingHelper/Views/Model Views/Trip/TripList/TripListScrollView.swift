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
    
    var trips: [Trip]
    var canShowCTA: Bool = false
    /// Leads with the past trips summary card
    var showsPastTripsSummary: Bool = false
    
    //    var shouldShowCTA: Bool {
    //        !purchaseManager.hasUnlockedPlus && canShowCTA && trips.count >= Trip.maxFreeTrips
    //    }
    //
    //    func shouldDisable(index: Int) -> Bool {
    //        !purchaseManager.hasUnlockedPlus && index >= Trip.maxFreeTrips && canShowCTA
    //    }
    //    Temporary force enable until purchases are figured out
    func shouldDisable(index: Int) -> Bool {
        return false
    }
    
    func deleteTrip() {
        if let trip = tripToDelete {
            SectionCollapseStateManager.removeState(for: trip.uuid)
            modelContext.delete(trip)
        }
    }
    
    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                let enumerated = Array(trips.enumerated())

                if showsPastTripsSummary {
                    PastTripsSummaryCard(path: $path, trips: trips) { trip in
                        reviewingTrip = trip
                    }
                    .modifier(TripCardPageStyle())
                }

                ForEach(enumerated, id: \.element.id) { index, trip in
                    // Use ZStack to guarantee a hittable layer
                    ZStack {
                        TripListRowView(trip: trip, disabled: shouldDisable(index: index))
                            // Display only; the layer below takes taps. Keeps row content that draws past the
                            // card's edges from swallowing taps meant for neighboring cards.
                            .allowsHitTesting(false)
                        
                        Color.clear
                            .contentShape(RoundedRectangle(cornerRadius: defaultCornerRadius))
                            .onTapGesture {
                                if !shouldDisable(index: index) {
                                    path.append(trip)
                                }
                            }
                    }
                    .modifier(TripCardPageStyle())
                    .contextMenu {
                        Button(role: .destructive) {
                            tripToDelete = trip
                            showTripDeleteAlert.toggle()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } preview: {
                        TripListRowView(trip: trip, disabled: false)
                            .frame(width: 300, height: 440)
                            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 10))
                    }
                }
                
                //                if shouldShowCTA {
                //                    PackingHelperPlusCTA(headerText: "Add unlimited trips with", version: .tall)
                //                        .containerRelativeFrame(.horizontal, count: 1, spacing: 16)
                //                        .scrollTransition { content, phase in
                //                            content
                //                                .opacity(phase.isIdentity ? 1.0 : 0.8)
                //                                .scaleEffect(y: phase.isIdentity ? 1.0 : 0.9)
                //                        }
                //                }
            }
            .scrollTargetLayout()
        }
        // Regular width (iPhone Duo unfolded, iPad): cards span the full screen width with standard edge padding
        .contentMargins(.horizontal, horizontalSizeClass == .regular ? 16 : 24, for: .scrollContent)
        .scrollTargetBehavior(.paging)
        // Presented from outside the scroll content so the summary card doesn't own the sheet
        .sheet(item: $reviewingTrip) { trip in
            TemplateUpdateSheet(sections: trip.templateCandidateSections) {
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

/// Sizes a card to one page of the trip pager
private struct TripCardPageStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical)
            .containerRelativeFrame(.horizontal, count: 1, spacing: 16)
            .scrollTransition { content, phase in
                content
                    .opacity(phase.isIdentity ? 1.0 : 0.8)
                    .scaleEffect(y: phase.isIdentity ? 1.0 : 0.9)
            }
    }
}

//#Preview {
//    TripListScrollView()
//}

