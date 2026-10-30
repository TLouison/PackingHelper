//
//  StyleUtilities.swift
//  PackingHelper
//
//  Created by Todd Louison on 10/22/23.
//

import SwiftUI

let defaultCornerRadius: CGFloat = 16

let defaultLinearGradient: LinearGradient = LinearGradient(colors: [.accentColor, .purple], startPoint: .leading, endPoint: .trailing)

let suitcaseIcon: String = "suitcase.rolling.fill"
let suitcaseDayOfIcon: String = "DayOfPacking"
let checklistDayOfIcon: String = "DayOfTask"
let defaultPackingListIcon: String = suitcaseIcon
let userIcon: String = "person.circle"

func pluralizeString(_ string: String, count: Int) -> String {
    count == 1 ? string : string + "s"
}

extension Animation {
    static let packingSpring = Animation.spring(response: 0.3, dampingFraction: 0.8)
}
