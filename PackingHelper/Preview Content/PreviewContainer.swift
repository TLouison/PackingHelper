//
//  PreviewContainer.swift
//  PackingHelper
//
//  Created by Todd Louison on 10/11/23.
//

import Foundation
import SwiftData

let previewContainer: ModelContainer = {
    do {
        let container = try ModelContainer(
            for: Trip.self, TripLocation.self, PackingList.self, Item.self, TripCoverPhoto.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        
        Task { @MainActor in
            let context = container.mainContext
            
            let origin = TripLocation.sampleOrigin
            let destination = TripLocation.sampleDestination
            context.insert(origin)
            context.insert(destination)
            context.insert(Trip(name: "NYC", startDate: Date.now, endDate: Date.now, types: [.plane], origin: origin, destination: destination, accomodations: [.hotel]))
        }
        return container
    } catch {
        fatalError("Failed to create container")
    }
}()

