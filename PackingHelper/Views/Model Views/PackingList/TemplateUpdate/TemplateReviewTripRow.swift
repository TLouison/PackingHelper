//
//  TemplateReviewTripRow.swift
//  PackingHelper
//
//  A past trip with items to save back to its templates: review, dismiss, or open the trip.
//  Shared by the Your Travels card and the Templates tab.
//

import SwiftUI
import SwiftData

struct TemplateReviewTripRow: View {
    let trip: Trip
    let onReview: () -> Void
    let onDismiss: () -> Void
    /// Opens the trip; when nil, tapping the row starts the review instead
    var onOpen: (() -> Void)? = nil

    var body: some View {
        let itemCount = trip.templateCandidateCount

        HStack(spacing: 12) {
            Button(action: onOpen ?? onReview) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("^[\(itemCount) item](inflect: true) not in your templates")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button("Review", action: onReview)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss review for \(trip.name)")
        }
        .roundedBox(background: .ultraThick)
    }
}

@available(iOS 18.0, *)
#Preview(traits: .sampleData) {
    @Previewable @Query var trips: [Trip]
    if let trip = trips.first {
        TemplateReviewTripRow(trip: trip) {} onDismiss: {}
            .padding()
    }
}
