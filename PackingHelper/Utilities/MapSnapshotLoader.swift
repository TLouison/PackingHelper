//
//  MapSnapshotLoader.swift
//  PackingHelper
//
//  Renders and caches static map images for trip cards, so the list doesn't
//  keep a live map view per card. Snapshots are cached in memory by
//  coordinates, size, scale, and light/dark appearance.
//

import MapKit
import UIKit

/// What to render: a muted, point-of-interest-free city map around a coordinate.
struct MapSnapshotRequest: Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let latitudeDelta: Double
    let longitudeDelta: Double
    /// Point size, rounded up to a multiple of `sizeStep` so small layout changes share a snapshot.
    let width: Int
    let height: Int
    let scale: Int
    let isDark: Bool

    static let sizeStep = 8

    init?(
        center: CLLocationCoordinate2D,
        span: MKCoordinateSpan,
        size: CGSize,
        displayScale: CGFloat,
        isDark: Bool
    ) {
        guard size.width > 0, size.height > 0 else { return nil }
        latitude = center.latitude
        longitude = center.longitude
        latitudeDelta = span.latitudeDelta
        longitudeDelta = span.longitudeDelta
        width = Self.roundedUp(size.width)
        height = Self.roundedUp(size.height)
        scale = max(Int(displayScale.rounded()), 1)
        self.isDark = isDark
    }

    private static func roundedUp(_ value: CGFloat) -> Int {
        Int((value / CGFloat(sizeStep)).rounded(.up)) * sizeStep
    }

    fileprivate var cacheKey: NSString {
        "\(latitude),\(longitude),\(latitudeDelta),\(longitudeDelta),\(width)x\(height)@\(scale)x_\(isDark ? "dark" : "light")" as NSString
    }
}

@MainActor
final class MapSnapshotLoader {
    static let shared = MapSnapshotLoader()

    private let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 60 * 1024 * 1024
        return cache
    }()

    private var inFlight: [MapSnapshotRequest: Task<UIImage?, Never>] = [:]

    /// Memory-cache hit, for showing a map on first render.
    func cachedImage(for request: MapSnapshotRequest) -> UIImage? {
        memory.object(forKey: request.cacheKey)
    }

    func image(for request: MapSnapshotRequest) async -> UIImage? {
        if let cached = cachedImage(for: request) { return cached }
        if let existing = inFlight[request] { return await existing.value }

        let task = Task { await Self.render(request) }
        inFlight[request] = task
        let image = await task.value
        inFlight[request] = nil

        if let image {
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            memory.setObject(image, forKey: request.cacheKey, cost: cost)
        }
        return image
    }

    private static func render(_ request: MapSnapshotRequest) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: request.latitude, longitude: request.longitude),
            span: MKCoordinateSpan(latitudeDelta: request.latitudeDelta, longitudeDelta: request.longitudeDelta)
        )
        options.size = CGSize(width: request.width, height: request.height)
        options.traitCollection = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: request.isDark ? .dark : .light),
            UITraitCollection(displayScale: CGFloat(request.scale)),
        ])
        // Same look as the card's old live map: points of interest turn it into a street map,
        // and muted keeps the info bar readable
        let configuration = MKStandardMapConfiguration(emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration

        do {
            return try await MKMapSnapshotter(options: options).start().image
        } catch {
            AppLogger.location.error("Map snapshot failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
