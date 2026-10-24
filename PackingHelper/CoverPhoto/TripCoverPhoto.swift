//
//  TripCoverPhoto.swift
//  PackingHelper
//
//  A user-chosen photo shown instead of the destination map on the trip card
//  and the trip detail hero. Library photos are stored as downscaled JPEG
//  bytes; Unsplash photos are hotlinked (per the Unsplash API guidelines) and
//  cached on disk by CoverPhotoImageLoader.
//

import Foundation
import SwiftData
import SwiftUI

enum CoverPhotoSource: String, Codable {
    case library, unsplash
}

/// What a new trip shows before the user picks a cover photo. Stored in
/// `@AppStorage("defaultTripCover")`; only consulted when creating a trip.
enum DefaultTripCover: String, CaseIterable {
    /// A random Unsplash photo of the destination, picked in the new-trip form.
    case photo = "Photo"
    case map = "Map"
}

/// Properties needed to render a cover photo, shared by the persisted model and
/// the edit-time draft so both render through `CoverPhotoImageView`.
protocol CoverPhotoRepresentable {
    var uuid: UUID { get }
    var source: CoverPhotoSource { get }
    var focalX: Double { get }
    var focalY: Double { get }
    var zoom: Double { get }
    var imageData: Data? { get }
    var unsplashId: String? { get }
    var unsplashRawURL: String? { get }
    var colorHex: String? { get }
    var blurHash: String? { get }
}

extension CoverPhotoRepresentable {
    var focalPoint: UnitPoint { UnitPoint(x: focalX, y: focalY) }

    /// Zoom beyond aspect-fill, clamped to the supported range.
    var clampedZoom: Double { min(max(zoom, 1), CoverPhotoDraft.maxZoom) }

    /// Memory/disk cache identity. Unsplash photos share cache entries across
    /// trips; library photos are keyed by the photo record.
    var cacheKey: String {
        if source == .unsplash, let unsplashId { return "unsplash_\(unsplashId)" }
        return "library_\(uuid.uuidString)"
    }

    var placeholderColor: Color {
        colorHex.flatMap { Color(hex: $0) } ?? Color(.systemGray5)
    }
}

@Model
final class TripCoverPhoto: CoverPhotoRepresentable {
    var uuid: UUID = UUID()
    var source: CoverPhotoSource = CoverPhotoSource.library

    /// Focal point in unit coordinates (0...1); crops keep it as centered as possible.
    var focalX: Double = 0.5
    var focalY: Double = 0.5
    /// Extra zoom on top of aspect-fill (1 = just fills the frame).
    var zoom: Double = 1.0

    // Library only
    @Attribute(.externalStorage) var imageData: Data?

    // Unsplash only
    var unsplashId: String?
    /// `urls.raw`; sized with imgix params at load time.
    var unsplashRawURL: String?
    var unsplashHTMLLink: String?
    var photographerName: String?
    var photographerUsername: String?
    var photographerProfileURL: String?
    var colorHex: String?
    var blurHash: String?

    var trip: Trip?
    var createdDate: Date = Date.now

    init(draft: CoverPhotoDraft) {
        self.uuid = draft.uuid
        self.source = draft.source
        self.focalX = draft.focalX
        self.focalY = draft.focalY
        self.zoom = draft.zoom
        self.imageData = draft.imageData
        self.unsplashId = draft.unsplashId
        self.unsplashRawURL = draft.unsplashRawURL
        self.unsplashHTMLLink = draft.unsplashHTMLLink
        self.photographerName = draft.photographerName
        self.photographerUsername = draft.photographerUsername
        self.photographerProfileURL = draft.photographerProfileURL
        self.colorHex = draft.colorHex
        self.blurHash = draft.blurHash
    }
}

// MARK: - Draft

/// Edit-time copy of a cover photo. `TripEditView` stages changes here and only
/// writes them to the trip on Save.
struct CoverPhotoDraft: CoverPhotoRepresentable, Identifiable, Equatable {
    var uuid: UUID = UUID()
    var source: CoverPhotoSource
    var focalX: Double = 0.5
    var focalY: Double = 0.5
    var zoom: Double = 1.0

    static let maxZoom: Double = 3

    var imageData: Data?

    var unsplashId: String?
    var unsplashRawURL: String?
    var unsplashHTMLLink: String?
    var photographerName: String?
    var photographerUsername: String?
    var photographerProfileURL: String?
    var colorHex: String?
    var blurHash: String?

    /// Set only for a freshly picked Unsplash photo. Saving the trip sends it to
    /// Unsplash's download-tracking endpoint; Cancel never does.
    var pendingDownloadLocation: String?

    var id: UUID { uuid }

    init(libraryImageData: Data) {
        self.source = .library
        self.imageData = libraryImageData
    }

    init(unsplash photo: UnsplashPhoto) {
        self.source = .unsplash
        self.unsplashId = photo.id
        self.unsplashRawURL = photo.urls.raw
        self.unsplashHTMLLink = photo.htmlLink
        self.photographerName = photo.photographer.name
        self.photographerUsername = photo.photographer.username
        self.photographerProfileURL = photo.photographer.profileURL
        self.colorHex = photo.color
        self.blurHash = photo.blurHash
        self.pendingDownloadLocation = photo.downloadLocation
    }

    init(_ photo: TripCoverPhoto) {
        self.uuid = photo.uuid
        self.source = photo.source
        self.focalX = photo.focalX
        self.focalY = photo.focalY
        self.zoom = photo.zoom
        self.imageData = photo.imageData
        self.unsplashId = photo.unsplashId
        self.unsplashRawURL = photo.unsplashRawURL
        self.unsplashHTMLLink = photo.unsplashHTMLLink
        self.photographerName = photo.photographerName
        self.photographerUsername = photo.photographerUsername
        self.photographerProfileURL = photo.photographerProfileURL
        self.colorHex = photo.colorHex
        self.blurHash = photo.blurHash
    }
}

// MARK: - Trip

extension Trip {
    /// Writes a staged cover photo to the trip. `nil` removes the photo (back to the map).
    func applyCoverPhoto(_ draft: CoverPhotoDraft?, in context: ModelContext) {
        if let existing = coverPhoto, existing.uuid == draft?.uuid, let draft {
            // Same photo; only the framing can have changed.
            existing.focalX = draft.focalX
            existing.focalY = draft.focalY
            existing.zoom = draft.zoom
            return
        }

        if let existing = coverPhoto {
            coverPhoto = nil
            context.delete(existing)
        }

        if let draft {
            let photo = TripCoverPhoto(draft: draft)
            context.insert(photo)
            coverPhoto = photo
        }
    }
}
