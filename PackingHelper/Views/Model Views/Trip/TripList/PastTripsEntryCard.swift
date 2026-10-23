//
//  PastTripsEntryCard.swift
//  PackingHelper
//
//  Trailing card in the upcoming trips list that opens past trips.
//

import SwiftUI
import SwiftData

struct PastTripsEntryCard: View {
    /// Completed trips, most recently finished first
    let trips: [Trip]

    let onOpen: () -> Void

    /// Past trips with items that could be saved back to their templates
    private var reviewCount: Int {
        trips.count(where: \.showsTemplateReviewCard)
    }

    var body: some View {
        let reviewCount = self.reviewCount

        Button(action: onOpen) {
            VStack(spacing: 16) {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accentColor.gradient)

                VStack(spacing: 4) {
                    Text("Your Travels")
                        .font(.title.bold())
                    Text("^[\(trips.count) past trip](inflect: true)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if reviewCount > 0 {
                    HStack(spacing: 6) {
                        UnreadBadge(count: reviewCount)
                        Text("^[\(reviewCount) trip](inflect: true) with items to review")
                            .font(.subheadline.weight(.semibold))
                    }
                }

                Label("View Past Trips", systemImage: "chevron.right")
                    .labelStyle(TrailingIconLabelStyle())
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
            }
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    Color(.secondarySystemBackground)
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.25), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: defaultCornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: defaultCornerRadius))
            .shadow(radius: defaultShadowRadius)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your Travels")
        .accessibilityValue(
            reviewCount > 0
                ? Text("^[\(trips.count) past trip](inflect: true), ^[\(reviewCount) trip](inflect: true) with items to review")
                : Text("^[\(trips.count) past trip](inflect: true)")
        )
        .accessibilityHint("Opens past trips")
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

@available(iOS 18.0, *)
#Preview(traits: .sampleData) {
    @Previewable @Query var trips: [Trip]
    PastTripsEntryCard(trips: trips) {}
        .frame(height: 440)
        .padding()
}
