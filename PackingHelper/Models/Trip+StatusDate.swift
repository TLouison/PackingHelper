//
//  Trip+StatusDate.swift
//  PackingHelper
//

import SwiftUI

extension Trip {
    /// When the trip leaves or returns, with the matching transport icon (trip detail hero)
    var statusDateText: some View {
        let calendar = Calendar.current
        let now = Date.now
        let beginDateString = startDate.formatted(date: .abbreviated, time: .omitted)
        let endDateString = endDate.formatted(date: .abbreviated, time: .omitted)

        return Group {
            if calendar.isDateInToday(startDate) {
                Label { Text("Departing today!") } icon: { primaryType.startIcon }
            } else if now < startDate {
                Label { Text("Departing on \(beginDateString)") } icon: { primaryType.startIcon }
            } else if calendar.isDateInToday(endDate) {
                Label { Text("Returning today") } icon: { primaryType.endIcon }
            } else if now < endDate {
                Label { Text("Returning on \(endDateString)") } icon: { primaryType.endIcon }
            } else {
                Label { Text("Returned on \(endDateString)") } icon: { primaryType.endIcon }
            }
        }
    }
}
