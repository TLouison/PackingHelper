//
//  SampleData.swift
//  PackingHelper
//
//  Created by Todd Louison on 6/19/24.
//

import SwiftUI
import SwiftData

@available(iOS 18.0, *)
struct SampleData: PreviewModifier {
    static func makeSharedContext() async throws -> Context {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Trip.self, TripLocation.self, PackingList.self, Item.self, User.self, TripCoverPhoto.self, configurations: config)
        
        makeSamples(in: container)
        
        return container
    }
    
    func body(content: Content, context: ModelContainer) -> some View {
        content.modelContainer(context)
    }
}

@available(iOS 18.0, *)
extension PreviewTrait where T == Preview.ViewTraits {
    @MainActor static var sampleData: Self = .modifier(SampleData())
}

@MainActor private func makeSamples(in container: ModelContainer) {
    // User Creation
    let userTodd = User(name: "Todd")
    let userEmma = User(name: "Emma")
    
    // Trip and Location Creation
    let springBreakLocations = [
        TripLocation(name: "New York City", latitude: 40.7128, longitude: -74.0060),
        TripLocation(name: "Miami", latitude: 25.7617, longitude: 80.1918)
    ]
    let springBreakTrip = Trip(name: "Spring Break", startDate: Date.distantPast, endDate: Date.distantPast.advanced(by: SECONDS_IN_DAY), type: .plane, origin: springBreakLocations[0], destination: springBreakLocations[1], accomodation: .rental)
    
    let familyVisitLocations = [
        TripLocation(name: "New York City", latitude: 40.7128, longitude: -74.0060),
        TripLocation(name: "Jersey City", latitude: 40.7178, longitude: -74.0431)
    ]
    let familyVisitTrip = Trip(name: "Family Visit", startDate: Date.distantPast, endDate: Date.distantFuture, type: .car, origin: familyVisitLocations[0], destination: familyVisitLocations[1], accomodation: .rental)
    
    let workTripLocations = [
        TripLocation(name: "New York City", latitude: 40.7128, longitude: -74.0060),
        TripLocation(name: "Amsterdam", latitude: 52.3676, longitude: 4.9041)
    ]
    let workTrip = Trip(name: "Work Trip", startDate: Date.distantFuture.advanced(by: -SECONDS_IN_DAY), endDate: Date.distantFuture, type: .car, origin: workTripLocations[0], destination: workTripLocations[1], accomodation: .hotel)
    
    // Packing List Creation (sections — user is on items, not lists)
    let springBreakBeachwear = PackingList(template: false, name: "Beachwear", countAsDays: true)
    let sbItem1 = Item(name: "Board Shorts", category: "Clothing", count: 2, isPacked: false, type: .packing)
    sbItem1.user = userEmma
    let sbItem2 = Item(name: "Bikini", category: "Clothing", count: 3, isPacked: true, type: .packing)
    sbItem2.user = userEmma
    let sbItem3 = Item(name: "Sunscreen", category: "Clothing", count: 1, isPacked: true, type: .packing)
    sbItem3.user = userEmma
    let sbItem4 = Item(name: "Sunglasses", category: "Accessories", count: 2, isPacked: false, type: .packing)
    sbItem4.user = userEmma
    springBreakBeachwear.addItem(sbItem1)
    springBreakBeachwear.addItem(sbItem2)
    springBreakBeachwear.addItem(sbItem3)
    springBreakBeachwear.addItem(sbItem4)
    springBreakBeachwear.trip = springBreakTrip
    
    let familyVisitEssentials = PackingList(template: false, name: "Essentials", countAsDays: true)
    let fvItem1 = Item(name: "Shirts", category: "Clothing", count: 5, isPacked: false, type: .packing)
    fvItem1.user = userTodd
    let fvItem2 = Item(name: "Shorts", category: "Clothing", count: 3, isPacked: true, type: .packing)
    fvItem2.user = userTodd
    let fvItem3 = Item(name: "Shoes", category: "Clothing", count: 1, isPacked: true, type: .packing)
    fvItem3.user = userTodd
    let fvItem4 = Item(name: "Gifts", category: "Accessories", count: 2, isPacked: false, type: .packing)
    fvItem4.user = userTodd
    familyVisitEssentials.addItem(fvItem1)
    familyVisitEssentials.addItem(fvItem2)
    familyVisitEssentials.addItem(fvItem3)
    familyVisitEssentials.addItem(fvItem4)
    familyVisitEssentials.trip = familyVisitTrip
    
    let workTripBizAttire = PackingList(template: false, name: "Business Attire", countAsDays: false)
    let wtItem1 = Item(name: "Suit Jacket", category: "Clothing", count: 1, isPacked: false, type: .packing)
    wtItem1.user = userEmma
    let wtItem2 = Item(name: "Dress Shirt", category: "Clothing", count: 3, isPacked: true, type: .packing)
    wtItem2.user = userEmma
    let wtItem3 = Item(name: "Dress", category: "Clothing", count: 1, isPacked: true, type: .packing)
    wtItem3.user = userEmma
    let wtItem4 = Item(name: "Shoes", category: "Accessories", count: 2, isPacked: false, type: .packing)
    wtItem4.user = userEmma
    workTripBizAttire.addItem(wtItem1)
    workTripBizAttire.addItem(wtItem2)
    workTripBizAttire.addItem(wtItem3)
    workTripBizAttire.addItem(wtItem4)
    workTripBizAttire.trip = workTrip
    
    let workTripChecklist = PackingList(template: false, name: "International Travel Checklist", countAsDays: false)
    let chkItem1 = Item(name: "Find Passport", category: "Task", count: 1, isPacked: false, type: .task)
    chkItem1.user = userEmma
    let chkItem2 = Item(name: "File for travel visa", category: "Task", count: 1, isPacked: true, type: .task)
    chkItem2.user = userEmma
    workTripChecklist.addItem(chkItem1)
    workTripChecklist.addItem(chkItem2)
    workTripChecklist.trip = workTrip
    
    let workTripMorningOf = PackingList(template: false, name: "Morning Of", countAsDays: true)
    let moItem1 = Item(name: "Take Out Trash", category: "Task", count: 1, isPacked: false, type: .task, isDayOf: true)
    moItem1.user = userEmma
    let moItem2 = Item(name: "Kiss Todd", category: "Task", count: 1, isPacked: true, type: .task, isDayOf: true)
    moItem2.user = userEmma
    workTripMorningOf.addItem(moItem1)
    workTripMorningOf.addItem(moItem2)
    workTripMorningOf.trip = workTrip
    
    // One default catch-all list per trip (v2 model)
    let springBreakDefault = PackingList(template: false, name: PackingList.defaultListName, countAsDays: false, sortOrder: -1)
    springBreakDefault.isDefault = true
    springBreakDefault.trip = springBreakTrip

    let familyVisitDefault = PackingList(template: false, name: PackingList.defaultListName, countAsDays: false, sortOrder: -1)
    familyVisitDefault.isDefault = true
    familyVisitDefault.trip = familyVisitTrip

    let workTripDefault = PackingList(template: false, name: PackingList.defaultListName, countAsDays: false, sortOrder: -1)
    workTripDefault.isDefault = true
    workTripDefault.trip = workTrip

    // Template lists
    let defaultPackingList = PackingList(template: true, name: "Essential Clothing", countAsDays: true)
    defaultPackingList.addItem(Item(name: "Shirts", category: "Clothing", count: 1, isPacked: false, type: .packing))
    defaultPackingList.addItem(Item(name: "Pants", category: "Clothing", count: 3, isPacked: true, type: .packing))
    defaultPackingList.addItem(Item(name: "Underwear", category: "Clothing", count: 1, isPacked: true, type: .packing))
    defaultPackingList.addItem(Item(name: "Socks", category: "Accessories", count: 2, isPacked: false, type: .packing))

    let defaultElectronicsPackingList = PackingList(template: true, name: "Electronics", countAsDays: false)
    defaultElectronicsPackingList.addItem(Item(name: "Phone", category: "Electronics", count: 1, isPacked: false, type: .packing))
    defaultElectronicsPackingList.addItem(Item(name: "Phone Charger", category: "Electronics", count: 1, isPacked: true, type: .packing))
    defaultElectronicsPackingList.addItem(Item(name: "Laptop", category: "Electronics", count: 1, isPacked: true, type: .packing))
    defaultElectronicsPackingList.addItem(Item(name: "Laptop Charger", category: "Electronics", count: 1, isPacked: false, type: .packing))

    container.mainContext.insert(userTodd)
    container.mainContext.insert(userEmma)
    
    container.mainContext.insert(defaultPackingList)
    container.mainContext.insert(defaultElectronicsPackingList)

    container.mainContext.insert(springBreakDefault)
    container.mainContext.insert(familyVisitDefault)
    container.mainContext.insert(workTripDefault)

    container.mainContext.insert(springBreakTrip)
    container.mainContext.insert(familyVisitTrip)
    container.mainContext.insert(workTrip)
}
