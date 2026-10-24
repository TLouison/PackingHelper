//
//  EmptyStateButton.swift
//  PackingHelper
//
//  The action button for empty states: extra-large and up to 280pt wide. Filled glass for the
//  main action, plain glass for a secondary one.
//

import SwiftUI

struct EmptyStateButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    var isProminent = true
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            EmptyStateButtonLabel(title: title, systemImage: systemImage)
        }
        .controlSize(.extraLarge)

        if isProminent {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
        }
    }
}

/// The label alone, for menus that open from an empty state (style them `.glassProminent`, `.extraLarge`)
struct EmptyStateButtonLabel: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .fontWeight(.semibold)
            .frame(maxWidth: 280)
    }
}

#Preview {
    VStack {
        EmptyStateButton(title: "Create Trip", systemImage: "plus") {}
        EmptyStateButton(title: "View Past Trips", systemImage: "clock.arrow.circlepath", isProminent: false) {}
    }
    .padding()
}
