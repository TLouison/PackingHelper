//
//  PastTripsSummaryCard.swift
//  PackingHelper
//
//  Leading card in the past trips pager: trips with items to save back to templates
//  and recently ended trips.
//

import SwiftUI
import SwiftData

struct PastTripsSummaryCard: View {
    @Binding var path: NavigationPath

    /// Completed trips, most recently finished first
    let trips: [Trip]

    /// Presented by the pager, outside its scroll content
    let onReview: (Trip) -> Void

    private static let recentTripLimit = 3

    private var reviewTrips: [Trip] {
        trips.filter(\.showsTemplateReviewCard)
    }

    /// Latest trips not already listed under review
    private var recentTrips: [Trip] {
        Array(trips.filter { !$0.showsTemplateReviewCard }.prefix(Self.recentTripLimit))
    }

    var body: some View {
        let reviewTrips = self.reviewTrips
        let recentTrips = self.recentTrips

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label("Your Travels", systemImage: "globe.americas.fill")
                    .font(.title.bold())
                    .foregroundStyle(Color.accentColor.gradient)

                if !reviewTrips.isEmpty {
                    section("Items to Review", systemImage: "exclamationmark.circle.fill", tint: .orange) {
                        ForEach(reviewTrips) { trip in
                            TemplateReviewTripRow(trip: trip) {
                                onReview(trip)
                            } onDismiss: {
                                withAnimation {
                                    trip.templateReviewDismissed = true
                                }
                            } onOpen: {
                                path.append(trip)
                            }
                        }
                    }
                }

                if !recentTrips.isEmpty {
                    section("Recently Ended", systemImage: "clock.arrow.circlepath", tint: .secondary) {
                        ForEach(recentTrips) { trip in
                            RecentTripRow(trip: trip) {
                                path.append(trip)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .scrollIndicators(.hidden)
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
        .shadow(radius: defaultShadowRadius)
    }

    private func section<Content: View>(
        _ title: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .labelStyle(TintedIconLabelStyle(tint: tint))
            content()
        }
    }
}

private struct TintedIconLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}

// MARK: - Rows

private struct RecentTripRow: View {
    let trip: Trip
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                trip.type.endIcon
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Ended \(trip.endDate.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            // Box inside the label so its padding is part of the tap target
            .roundedBox(background: .ultraThick)
        }
        .buttonStyle(.plain)
    }
}

@available(iOS 18.0, *)
#Preview(traits: .sampleData) {
    @Previewable @Query var trips: [Trip]
    PastTripsSummaryCard(path: .constant(NavigationPath()), trips: trips) { _ in }
        .padding()
}
