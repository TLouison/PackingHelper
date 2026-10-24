//
//  CoverPhotoSection.swift
//  PackingHelper
//
//  "Cover Photo" content for TripEditView. Edits a staged draft only; the trip
//  is updated when the edit is saved.
//

import SwiftUI
import PhotosUI

struct CoverPhotoSection: View {
    @Binding var draft: CoverPhotoDraft?
    let destinationName: String?
    let tripName: String

    @Environment(PurchaseManager.self) private var purchaseManager

    @State private var libraryItem: PhotosPickerItem?
    @State private var showingLibraryPicker = false
    @State private var showingUnsplashPicker = false
    @State private var pendingFocus: CoverPhotoDraft?
    @State private var isProcessing = false
    @State private var loadError: String?

    var body: some View {
        HStack(spacing: 16) {
            thumbnail

            VStack(alignment: .leading, spacing: 8) {
                Text(sourceDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let loadError {
                    Text(loadError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                menu
            }

            Spacer(minLength: 0)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 15))
        .photosPicker(isPresented: $showingLibraryPicker, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task { await processLibraryPick(item) }
        }
        .sheet(item: $pendingFocus) { pending in
            NavigationStack {
                CoverPhotoFocusView(
                    draft: pending,
                    onCancel: { pendingFocus = nil },
                    onDone: { focused in
                        draft = focused
                        pendingFocus = nil
                    }
                )
            }
        }
        .sheet(isPresented: $showingUnsplashPicker) {
            UnsplashPickerView(
                initialQuery: UnsplashPickerView.initialQuery(forDestination: destinationName),
                fallbackQuery: tripName
            ) { picked in
                draft = picked
            }
        }
    }

    // MARK: - Pieces

    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(.tertiarySystemGroupedBackground))
            .overlay {
                if let draft {
                    CoverPhotoImageView(photo: draft)
                } else {
                    Image(systemName: "map")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .overlay {
                if isProcessing {
                    ProgressView()
                }
            }
            .frame(width: 90, height: 132)
            .clipShape(.rect(cornerRadius: 10))
            .accessibilityHidden(true)
    }

    private var sourceDescription: String {
        guard let draft else { return "Uses the destination map." }
        switch draft.source {
        case .library:
            return "From your photo library."
        case .unsplash:
            return "Photo by \(draft.photographerName ?? "Unknown") on Unsplash."
        }
    }

    private var menu: some View {
        Menu {
            Button {
                showingLibraryPicker = true
            } label: {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
            }

            Button {
                showingUnsplashPicker = true
            } label: {
                if purchaseManager.isPlusActive {
                    Label("Search Unsplash", systemImage: "magnifyingglass")
                } else {
                    Label("Browse Unsplash", systemImage: "photo.on.rectangle.angled")
                }
            }

            if let draft {
                Divider()

                Button {
                    pendingFocus = draft
                } label: {
                    Label("Adjust Focus", systemImage: "viewfinder")
                }

                Button(role: .destructive) {
                    self.draft = nil
                } label: {
                    Label("Remove Photo", systemImage: "trash")
                }
            }
        } label: {
            Text(draft == nil ? "Choose Photo" : "Change Photo")
                .font(.subheadline.weight(.semibold))
        }
        .disabled(isProcessing)
    }

    // MARK: - Library

    private func processLibraryPick(_ item: PhotosPickerItem) async {
        isProcessing = true
        loadError = nil

        let data = try? await item.loadTransferable(type: Data.self)
        let prepared = await Task.detached(priority: .userInitiated) {
            data.flatMap(CoverPhotoProcessing.preparedJPEG(from:))
        }.value

        isProcessing = false
        libraryItem = nil

        guard let prepared else {
            loadError = "Couldn't load that photo."
            return
        }
        pendingFocus = CoverPhotoDraft(libraryImageData: prepared)
    }
}
