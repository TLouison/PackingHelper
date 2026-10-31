//
//  DayOfBadge.swift
//  PackingHelper
//
//  The small sunrise after a day-of item's name (`Item.isDayOf`). Left off the Day Of page,
//  where every card would have one. Takes its size from the environment font.
//

import SwiftUI

struct DayOfBadge: View {
    var body: some View {
        Image(systemName: dayOfIcon)
            .foregroundStyle(.orange)
            .accessibilityLabel("Day Of")
    }
}

/// Hold menu action that flags or unflags an item as day-of
struct DayOfToggleButton: View {
    let item: Item

    var body: some View {
        Button(item.isDayOf ? "Remove from Day Of" : "Mark as Day Of", systemImage: dayOfIcon) {
            withAnimation(.packingSpring) { item.isDayOf.toggle() }
        }
    }
}

#Preview {
    HStack(spacing: 4) {
        Text("Toothbrush")
        DayOfBadge()
    }
    .font(.body.weight(.medium))
}
