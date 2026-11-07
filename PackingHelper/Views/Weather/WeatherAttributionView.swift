//
//  WeatherAttributionView.swift
//  PackingHelper
//
//  The Apple Weather mark and a link to WeatherKit's data sources, which WeatherKit's
//  terms require. Shown in trip detail's credits and Settings › About. The trip list
//  cards' weather has none, by choice; if App Review objects, attribute there too.
//

import SwiftUI
import WeatherKit

struct WeatherAttributionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var attribution: WeatherAttribution?

    /// Apple's attribution page, for when `WeatherAttribution` hasn't loaded (offline)
    private static let fallbackLegalURL = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!

    private var markURL: URL? {
        guard let attribution else { return nil }
        return colorScheme == .dark ? attribution.combinedMarkDarkURL : attribution.combinedMarkLightURL
    }

    var body: some View {
        HStack(spacing: 6) {
            AsyncImage(url: markURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(height: 12)
                } else {
                    Text("Apple Weather")
                }
            }
            .accessibilityLabel("Apple Weather")

            Text(verbatim: "·")
                .accessibilityHidden(true)

            Link("Other data sources", destination: attribution?.legalPageURL ?? Self.fallbackLegalURL)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .tint(.secondary)
        .task {
            attribution = await WeatherProvider.shared.attribution()
        }
    }
}

#Preview {
    WeatherAttributionView()
}
