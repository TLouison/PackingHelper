//
//  UnsplashPickerView.swift
//  PackingHelper
//
//  Searches Unsplash (via the Worker) for a trip cover photo. Opens with the
//  destination already searched; results come in pages of 12 behind a
//  "Load More" button to stay light on the shared Unsplash quota.
//

import SwiftUI

struct UnsplashPickerView: View {
    let onPick: (CoverPhotoDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseManager.self) private var purchaseManager

    @State private var query: String
    @State private var activeQuery = ""
    @State private var results: [UnsplashPhoto] = []
    @State private var page = 0
    @State private var totalPages = 0
    @State private var isLoading = false
    @State private var error: UnsplashServiceError?
    @State private var selectedPhoto: UnsplashPhoto?
    @State private var showingPaywall = false
    @State private var searchTask: Task<Void, Never>?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    init(initialQuery: String, onPick: @escaping (CoverPhotoDraft) -> Void) {
        self.onPick = onPick
        self._query = State(initialValue: initialQuery)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Unsplash")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search photos")
            .onSubmit(of: .search) { startSearch() }
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
                if purchaseManager.isPlusActive { startSearch() }
            }) {
                PlusPaywallView()
            }
            .task {
                if activeQuery.isEmpty { startSearch() }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if activeQuery.isEmpty {
            ContentUnavailableView(
                "Search Unsplash",
                systemImage: "photo.on.rectangle.angled",
                description: Text("Find a photo for your trip.")
            )
        } else if results.isEmpty {
            if isLoading {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(0..<12, id: \.self) { _ in skeletonCell }
                }
            } else if let error {
                errorView(error)
            } else {
                ContentUnavailableView.search(text: activeQuery)
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
        isLoading = false
        guard !trimmed.isEmpty else { return }
        searchTask = Task { await loadPage(1) }
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

extension UnsplashPickerView {
    /// "Lisbon, Portugal" → "Lisbon".
    static func initialQuery(forDestination name: String?) -> String {
        guard let name else { return "" }
        let city = name.split(separator: ",").first.map(String.init) ?? name
        return city.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
