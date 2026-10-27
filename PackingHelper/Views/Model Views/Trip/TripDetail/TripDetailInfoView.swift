//
//  TripDetailInfoView.swift
//  PackingHelper
//
//  Created by Todd Louison on 10/19/23.
//

import SwiftUI
import SwiftData

struct TripDetailInfoView: View {
    let trip: Trip
    
    var body: some View {
        TripDetailSectionView(title: "Trip Info") {
            VStack(spacing: 10) {
                InfoRow("Status", trip.getStatusLabel())
                InfoRow("Type", trip.getTypeLabel())
                InfoRow("Duration", Text("\(trip.duration) days"))
                
                if trip.daysUntilDeparture > 0 {
                    InfoRow("Days Until Departure", Text("\(trip.daysUntilDeparture) days"))
                } else if trip.daysUntilReturn > 0 {
                    InfoRow("Days Until Return", Text("\(trip.daysUntilReturn) days"))
                }
            }
        }
    }
}
