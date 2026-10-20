//
//  LocationSearchView.swift
//  PackingHelper
//
//  Created by Todd Louison on 9/15/25.
//


import SwiftUI
import MapKit

struct LocationSearchView: View {
    @Binding var location: TripLocation?
    var title: String = "Search Location"
    @Environment(\.dismiss) var dismiss

    @State private var completer = LocationCompleter()
    @State private var resolvingID: LocationCompleter.Suggestion.ID?
    @State private var resolveFailed = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                ForEach(completer.suggestions) { suggestion in
                    Button {
                        Task { await select(suggestion) }
                    } label: {
                        SuggestionRow(
                            suggestion: suggestion,
                            isResolving: resolvingID == suggestion.id
                        )
                    }
                    .disabled(resolvingID != nil)
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                emptyState
            }
            .searchable(
                text: $completer.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "City, landmark, or address"
            )
            .searchFocused($isSearchFocused)
            // Keep the nav bar (and its Cancel button) visible while the search is active,
            // so the sheet can be dismissed in one tap.
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .autocorrectionDisabled()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Couldn't load that location", isPresented: $resolveFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please try again or pick a different result.")
            }
            .onAppear {
                isSearchFocused = true
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let trimmed = completer.query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            ContentUnavailableView(
                "Find a Place",
                systemImage: "map",
                description: Text("Search for a city, landmark, or address.")
            )
        } else if completer.suggestions.isEmpty && !completer.isSearching {
            ContentUnavailableView.search(text: trimmed)
        }
    }

    private func select(_ suggestion: LocationCompleter.Suggestion) async {
        resolvingID = suggestion.id
        defer { resolvingID = nil }

        let request = MKLocalSearch.Request(completion: suggestion.completion)
        guard let mapItem = try? await MKLocalSearch(request: request).start().mapItems.first else {
            resolveFailed = true
            return
        }

        let coordinate = mapItem.location.coordinate
        location = TripLocation(
            name: mapItem.name ?? suggestion.completion.title,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        isSearchFocused = false
        dismiss()
    }
}

// MARK: - Row

private struct SuggestionRow: View {
    let suggestion: LocationCompleter.Suggestion
    let isResolving: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: suggestion.isPlace ? "mappin" : "globe.americas.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(suggestion.isPlace ? Color.red : Color.blue, in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.highlightedTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !suggestion.completion.subtitle.isEmpty {
                    Text(suggestion.completion.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if isResolving {
                ProgressView()
            }
        }
        .contentShape(.rect)
    }
}

// MARK: - Completer

/// Wraps MKLocalSearchCompleter, which returns Maps-style autocomplete suggestions
/// (e.g. "Paris, France", "Paris, TX") rather than the single best match that
/// MKLocalSearch resolves a natural-language query to.
@MainActor
@Observable
final class LocationCompleter: NSObject, MKLocalSearchCompleterDelegate {
    struct Suggestion: Identifiable {
        let completion: MKLocalSearchCompletion

        var id: String { completion.title + "|" + completion.subtitle }

        /// Heuristic: completions don't expose their type, but city/region results have
        /// a subtitle like "France" or "TX, United States", while specific places carry
        /// a street address or postal code. Places get a pin; cities get a globe.
        var isPlace: Bool {
            completion.subtitle.contains(where: \.isNumber)
        }

        var highlightedTitle: AttributedString {
            var text = AttributedString(completion.title)
            for value in completion.titleHighlightRanges {
                if let range = Range(value.rangeValue, in: text) {
                    text[range].inlinePresentationIntent = .stronglyEmphasized
                }
            }
            return text
        }
    }

    var query: String = "" {
        didSet { updateQuery() }
    }
    private(set) var suggestions: [Suggestion] = []
    private(set) var isSearching = false

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    private func updateQuery() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            completer.cancel()
            suggestions = []
            isSearching = false
        } else {
            isSearching = true
            completer.queryFragment = trimmed
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        MainActor.assumeIsolated {
            // De-dupe: the completer occasionally returns identical title/subtitle pairs.
            var seen = Set<String>()
            suggestions = results
                .map(Suggestion.init)
                .filter { seen.insert($0.id).inserted }
            isSearching = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            suggestions = []
            isSearching = false
        }
    }
}
