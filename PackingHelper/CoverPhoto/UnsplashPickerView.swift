//
//  UnsplashPickerView.swift
//  PackingHelper
//
//  Searches Unsplash (via the Worker) for a trip cover photo. Opens with the
//  destination already searched (falling back to the trip name when the
//  destination is missing or finds nothing); results come in pages of 25. Free users get
//  that first page only (no search bar, Load More upsells Plus); Plus users can
//  search and load more.
//

import SwiftUI

struct UnsplashPickerView: View {
    let onPick: (CoverPhotoDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseManager.self) private var purchaseManager

    @State private var query: String
    @State private var activeQuery = ""
    /// Tried once if the opening search comes back empty; cleared by any user search.
    @State private var fallbackQuery: String?
    /// Still showing the automatic destination/trip-name search, not one the user typed.
    @State private var isOpeningSearch = true
    @State private var results: [UnsplashPhoto] = []
    @State private var page = 0
    @State private var totalPages = 0
    @State private var isLoading = false
    @State private var error: UnsplashServiceError?
    @State private var selectedPhoto: UnsplashPhoto?
    @State private var showingPaywall = false
    @State private var searchTask: Task<Void, Never>?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    init(initialQuery: String, fallbackQuery: String = "", onPick: @escaping (CoverPhotoDraft) -> Void) {
        self.onPick = onPick
        let initial = initialQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = fallbackQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if initial.isEmpty {
            self._query = State(initialValue: fallback)
        } else {
            self._query = State(initialValue: initial)
            let isDistinct = !fallback.isEmpty && fallback.localizedCaseInsensitiveCompare(initial) != .orderedSame
            self._fallbackQuery = State(initialValue: isDistinct ? fallback : nil)
        }
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Unsplash")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(PlusSearchable(isEnabled: purchaseManager.isPlusActive, query: $query, onSubmit: submitSearch))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .navigationDestination(item: $selectedPhoto) { photo in
                    CoverPhotoFocusView(
                        draft: CoverPhotoDraft(unsplash: photo),
                        onCancel: { selectedPhoto = nil },
                        onDone: { draft in
                            onPick(draft)
                            dismiss()
                        }
                    )
                }
                .sheet(isPresented: $showingPaywall, onDismiss: {
                    // Keep what's loaded; Load More is available now.
                    if purchaseManager.isPlusActive, case .notSubscribed? = error { error = nil }
                }) {
                    PlusPaywallView()
                }
                .task {
                    if activeQuery.isEmpty { startSearch() }
                }
        }
    }

    // MARK: - Content

    /// Empty states fill the screen (centered); photos and loading skeletons scroll.
    @ViewBuilder
    private var content: some View {
        if !results.isEmpty || (isLoading && !activeQuery.isEmpty) {
            ScrollView {
                grid
                    .padding()
            }
        } else {
            emptyState
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if activeQuery.isEmpty {
            if purchaseManager.isPlusActive {
                ContentUnavailableView(
                    "Search Unsplash",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Find a photo for your trip.")
                )
            } else {
                ContentUnavailableView(
                    "No Destination",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Add a destination or trip name to see photos for it, or get Plus to search Unsplash.")
                )
            }
        } else if let error {
            errorView(error)
        } else if isOpeningSearch {
            noTripPhotosView
        } else {
            ContentUnavailableView.search(text: activeQuery)
        }
    }

    @ViewBuilder
    private var grid: some View {
        if results.isEmpty {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(0..<12, id: \.self) { _ in skeletonCell }
            }
        } else {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(results) { photo in
                    resultCell(photo)
                }
            }

            footer
                .padding(.top, 20)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let error {
            VStack(spacing: 8) {
                Text(error.localizedDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") { loadMore() }
            }
        } else if page < totalPages && !purchaseManager.isPlusActive {
            plusLoadMoreButton
        } else if page < totalPages {
            Button {
                loadMore()
            } label: {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Load More")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isLoading)
        }
    }

    private var noTripPhotosView: some View {
        ContentUnavailableView {
            Label("No Trip Photos", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text(purchaseManager.isPlusActive
                ? "We couldn't find any photos related to your trip. Try searching for something else."
                : "We couldn't find any photos related to your trip. Get Plus to search Unsplash for something else, or choose one from your library.")
        } actions: {
            if !purchaseManager.isPlusActive {
                Button {
                    showingPaywall = true
                } label: {
                    Label("Get Plus to Search", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    /// Looks disabled but stays tappable so it can open the paywall.
    private var plusLoadMoreButton: some View {
        Button {
            showingPaywall = true
        } label: {
            VStack(spacing: 2) {
                Label("Load More", systemImage: "lock.fill")
                Text("Requires Plus")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
        .controlSize(.large)
        .accessibilityLabel("Load More")
        .accessibilityHint("Requires Packing Helper Plus. Opens the subscription screen.")
    }

    private func resultCell(_ photo: UnsplashPhoto) -> some View {
        Button {
            selectedPhoto = photo
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                thumbnailPlaceholder(photo)
                    .aspectRatio(3 / 2, contentMode: .fit)
                    .overlay {
                        AsyncImage(url: URL(string: photo.urls.small)) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .transition(.opacity)
                            }
                        }
                    }
                    .clipShape(.rect(cornerRadius: 10))

                Text(photo.photographer.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Photo by \(photo.photographer.name)")
    }

    private func thumbnailPlaceholder(_ photo: UnsplashPhoto) -> some View {
        ZStack {
            photo.color.flatMap { Color(hex: $0) } ?? Color(.systemGray5)

            if let hash = photo.blurHash, let blurred = BlurHash.image(from: hash, width: 24, height: 16) {
                Image(uiImage: blurred)
                    .resizable()
                    .scaledToFill()
            }
        }
    }

    private var skeletonCell: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray5))
                .aspectRatio(3 / 2, contentMode: .fit)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 80, height: 10)
        }
        .redacted(reason: .placeholder)
    }

    private func errorView(_ error: UnsplashServiceError) -> some View {
        ContentUnavailableView {
            Label("Couldn't Load Photos", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("Retry") { startSearch() }
                .buttonStyle(.bordered)
        }
    }

    // MARK: - Loading

    private func startSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        activeQuery = trimmed
        results = []
        page = 0
        totalPages = 0
        error = nil
        isLoading = !trimmed.isEmpty
        guard !trimmed.isEmpty else { return }
        searchTask = Task { await loadPage(1) }
    }

    private func submitSearch() {
        fallbackQuery = nil
        isOpeningSearch = false
        startSearch()
    }

    private func loadMore() {
        guard !isLoading else { return }
        searchTask = Task { await loadPage(page + 1) }
    }

    private func loadPage(_ nextPage: Int) async {
        let searchedQuery = activeQuery
        isLoading = true
        error = nil

        do {
            let response = try await UnsplashService.shared.search(query: searchedQuery, page: nextPage)
            guard !Task.isCancelled, searchedQuery == activeQuery else { return }

            if nextPage == 1, response.results.isEmpty, let fallback = fallbackQuery {
                fallbackQuery = nil
                query = fallback
                startSearch()
                return
            }

            let existing = Set(results.map(\.id))
            results += response.results.filter { !existing.contains($0.id) }
            page = response.page
            totalPages = response.totalPages
        } catch let serviceError as UnsplashServiceError {
            guard !Task.isCancelled, searchedQuery == activeQuery else { return }
            error = serviceError
            if case .notSubscribed = serviceError {
                await purchaseManager.refresh()
                showingPaywall = true
            }
        } catch {
            guard !Task.isCancelled, searchedQuery == activeQuery else { return }
            self.error = .network(error)
        }

        isLoading = false
    }
}

/// The search bar is a Plus feature; free users only see their destination.
private struct PlusSearchable: ViewModifier {
    let isEnabled: Bool
    @Binding var query: String
    let onSubmit: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search photos")
                .onSubmit(of: .search, onSubmit)
        } else {
            content
        }
    }
}

extension UnsplashPickerView {
    /// "Lisbon, Portugal" → "Lisbon".
    static func initialQuery(forDestination name: String?) -> String {
        guard let name else { return "" }
        let city = name.split(separator: ",").first.map(String.init) ?? name
        return city.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
