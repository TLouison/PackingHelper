//
//  TripListRowView.swift
//  PackingHelper
//
//  Created by Todd Louison on 10/13/23.
//

import SwiftUI
import SwiftData
import MapKit
import WeatherKit

struct TripListRowView: View {
    @Environment(\.modelContext) var modelContext

    @State private var showDeleteTripAlert: Bool = false
    @State private var featureFlags = FeatureFlags.shared
    @State private var cardWeather: CardWeather?
    /// Wide enough that a full-width info bar would stretch into a thin strip
    @State private var isWide: Bool = false

    @Bindable var trip: Trip

    /// The next departure, shown as the wide card above the grid
    var isFeatured: Bool = false

    /// Card width past which the featured card keeps its info bar to the leading side
    private static let wideCardWidth: CGFloat = 700
    private static let wideInfoBarWidth: CGFloat = 400

    /// Departure-day forecast (or current conditions) at the destination, inside the forecast window
    private struct CardWeather {
        let symbolName: String
        let temperature: String
    }

    private var dateRangeText: String {
        let start = trip.startDate.formatted(.dateTime.month(.abbreviated).day())
        let end = trip.endDate.formatted(date: .abbreviated, time: .omitted)
        return "\(start) – \(end)"
    }

    private var countdownText: Text {
        switch trip.status {
        case .upcoming:
            let days = trip.daysUntilDeparture
            switch days {
            case ...0: return Text("Today")
            case 1: return Text("Tomorrow")
            default: return Text("In ^[\(days) day](inflect: true)")
            }
        case .departing:
            return Text("Departing today")
        case .active:
            let days = trip.daysUntilReturn
            return days > 0 ? Text("^[\(days) day](inflect: true) left") : Text("Returning today")
        case .returning:
            return Text("Returning today")
        case .complete:
            return Text("Ended \(trip.endDate.formatted(.relative(presentation: .named)))")
        }
    }

    @ViewBuilder private var packingProgress: some View {
        let total = trip.totalItemsCount
        if total > 0 {
            let packed = trip.packedItemsCount
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(packed), total: Double(total))
                    .tint(packed == total ? .green : .accentColor)
                Text("\(packed) of \(total) packed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Name, place, dates, and packing progress in one glass bar along the bottom of the card
    private var infoBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.name)
                        .font(.title2.bold())
                        .lineLimit(2)
                    if let destination = trip.destination {
                        Label(destination.name, systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if let cardWeather {
                    VStack(spacing: 2) {
                        Image(systemName: cardWeather.symbolName)
                            .symbolRenderingMode(.multicolor)
                            .font(.title2)
                            .contentTransition(.symbolEffect(.replace))
                        Text(cardWeather.temperature)
                            .font(.caption.weight(.semibold))
                            .contentTransition(.numericText())
                    }
                    .accessibilityElement(children: .combine)
                    .transition(.blurReplace)
                }
            }

            // Side by side when both fit on one line; otherwise stacked rather than wrapping the countdown
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(dateRangeText)
                    Spacer(minLength: 8)
                    countdownText
                        .fontWeight(.semibold)
                }
                .lineLimit(1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(dateRangeText)
                    countdownText
                        .fontWeight(.semibold)
                }
            }
            .font(.subheadline)

            packingProgress
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Floats over the cover photo or map, so it keeps Liquid Glass
        .glassRoundedBox()
        .shaded()
        .overlay(alignment: .topTrailing) {
            if trip.showsTemplateReviewCard {
                UnreadBadge(count: trip.templateReviewCount)
                    .offset(x: 6, y: -6)
                    .accessibilityLabel("\(trip.templateReviewSummary) to review")
            }
        }
    }

    @ViewBuilder func tripRowOverlay(_ trip: Trip) -> some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                if featureFlags.showingMultiplePackers {
                    UserIndicators(users: trip.packers)
                        .padding(.leading)
                }
                Spacer()
                if isFeatured {
                    nextTripBadge
                }
            }
            Spacer()
            infoBar
                .frame(maxWidth: isFeatured && isWide ? Self.wideInfoBarWidth : .infinity, alignment: .leading)
        }
    }

    private var nextTripBadge: some View {
        Label {
            Text("Next Trip")
        } icon: {
            trip.primaryType.startIcon
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(.accentColor), in: .capsule)
        .shaded()
    }

    private func loadWeather() async {
        guard let destination = trip.destination,
              destination.canGetWeatherForecast(for: trip),
              let weather = await destination.getTripWeather(for: trip)
        else {
            cardWeather = nil
            return
        }

        let loaded: CardWeather? = if let day = weather.dailyForecast?.first {
            CardWeather(
                symbolName: day.symbolName,
                temperature: getCurrentWeatherFormattedTemperature(currentTemperature: day.highTemperature)
            )
        } else if let current = weather.currentWeather {
            CardWeather(
                symbolName: current.symbolName,
                temperature: getCurrentWeatherFormattedTemperature(currentTemperature: current.temperature)
            )
        } else {
            nil
        }
        withAnimation {
            cardWeather = loaded
        }
    }

    var body: some View {
        ZStack {
            tripRowOverlay(trip)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            TripBackgroundView(trip: trip, style: .card)
        }
        .clipShape(RoundedRectangle(cornerRadius: defaultCornerRadius))
        .shadow(radius: defaultShadowRadius)
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.size.width >= Self.wideCardWidth
        } action: { isWide in
            self.isWide = isWide
        }
        .task(id: trip.destination?.id) {
            await loadWeather()
        }
    }
}

struct UserIndicators: View {
    let users: [User]
    
    var body: some View {
        HStack {
            ForEach(users.sorted()) { user in
                user.pillFirstInitialIconSolid
            }
        }
        .scaleEffect(1.4, anchor: .top)
    }
}

