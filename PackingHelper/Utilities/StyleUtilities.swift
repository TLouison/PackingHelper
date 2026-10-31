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
/// Day-of items: their card badge, the Day Of chip, and the add bar toggle
let dayOfIcon: String = "sunrise"
let defaultPackingListIcon: String = suitcaseIcon
let userIcon: String = "person.circle"

func pluralizeString(_ string: String, count: Int) -> String {
    count == 1 ? string : string + "s"
}

extension Animation {
    static let packingSpring = Animation.spring(response: 0.3, dampingFraction: 0.8)
}
