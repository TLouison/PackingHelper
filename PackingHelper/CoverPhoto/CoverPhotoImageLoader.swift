//
//  CoverPhotoImageLoader.swift
//  PackingHelper
//
//  Loads and caches cover photo bitmaps. Unsplash photos are hotlinked from
//  images.unsplash.com at a bucketed width and kept on disk in
//  Caches/CoverPhotos so they still render offline; library photos are decoded
//  from their stored bytes. Decoded images live in a memory cache for both.
//

import UIKit
import ImageIO

/// Sendable description of what to load, extracted from a cover photo on the
/// main actor so model objects never cross into the loader.
struct CoverPhotoImageRequest: Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case library
        case unsplash(id: String, rawURL: String)
    }

    let cacheKey: String
    let source: Source
    /// Bucketed pixel width, so the card and the hero share cache entries.
    let pixelWidth: Int

    static let widthBuckets = [400, 800, 1200, 1600, 2000, 2400]

    init?(photo: some CoverPhotoRepresentable, pointSize: CGSize, displayScale: CGFloat) {
        guard pointSize.width > 0, pointSize.height > 0 else { return nil }

        switch photo.source {
        case .library:
            source = .library
        case .unsplash:
            guard let id = photo.unsplashId, let raw = photo.unsplashRawURL else { return nil }
            source = .unsplash(id: id, rawURL: raw)
        }
        cacheKey = photo.cacheKey

        // Aspect-fill: tall frames need a wider image than their own width.
        // Unsplash results are landscape (~3:2), so size for that.
        // Zooming in shows fewer source pixels per point, so ask for more.
        let neededWidth = max(pointSize.width, pointSize.height * 1.5) * displayScale * photo.clampedZoom
        pixelWidth = Self.widthBuckets.first { CGFloat($0) >= neededWidth } ?? Self.widthBuckets.last!
    }
}

actor CoverPhotoImageLoader {
    static let shared = CoverPhotoImageLoader()

    private nonisolated let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 120 * 1024 * 1024
        return cache
    }()

    private var inFlight: [CoverPhotoImageRequest: Task<UIImage?, Never>] = [:]

    private let directory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("CoverPhotos", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            AppLogger.coverPhoto.error("Couldn't create the cover photo cache directory: \(error.localizedDescription, privacy: .public)")
        }
        return dir
    }()

    /// Synchronous memory-cache hit, for showing an image on first render.
    nonisolated func cachedImage(for request: CoverPhotoImageRequest) -> UIImage? {
        memory.object(forKey: memoryKey(request))
    }

    /// `libraryData` is only read for library photos on a memory-cache miss.
    func image(for request: CoverPhotoImageRequest, libraryData: Data? = nil) async -> UIImage? {
        if let cached = cachedImage(for: request) { return cached }
        if let existing = inFlight[request] { return await existing.value }

        // Detached so network and decode work don't serialize on the actor.
        let task = Task.detached(priority: .userInitiated) { [directory] () -> UIImage? in
            switch request.source {
            case .library:
                guard let libraryData else { return nil }
                return Self.decode(libraryData, maxPixelSize: request.pixelWidth)
            case .unsplash(let id, let rawURL):
                return await Self.loadUnsplash(id: id, rawURL: rawURL, width: request.pixelWidth, directory: directory)
            }
        }
        inFlight[request] = task
        let image = await task.value
        inFlight[request] = nil

        if let image {
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            memory.setObject(image, forKey: memoryKey(request), cost: cost)
        }
        return image
    }

    private nonisolated func memoryKey(_ request: CoverPhotoImageRequest) -> NSString {
        "\(request.cacheKey)_\(request.pixelWidth)" as NSString
    }

    // MARK: - Unsplash

    private static func loadUnsplash(id: String, rawURL: String, width: Int, directory: URL) async -> UIImage? {
        let file = directory.appendingPathComponent("\(id)_\(width).jpg")
        if let data = readCachedFile(file), let image = decode(data, maxPixelSize: width) {
            return image
        }

        if let url = sizedURL(rawURL: rawURL, width: width) {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if (response as? HTTPURLResponse)?.statusCode == 200,
                   let image = decode(data, maxPixelSize: width) {
                    do {
                        try data.write(to: file, options: .atomic)
                    } catch {
                        AppLogger.coverPhoto.error("Couldn't cache \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    }
                    return image
                }
            } catch {
                // Routine when offline; the cached fallback below covers it
                AppLogger.coverPhoto.info("Couldn't download \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        // Offline or failed: fall back to any other cached size of this photo.
        return largestCachedVariant(id: id, directory: directory)
    }

    private static func sizedURL(rawURL: String, width: Int) -> URL? {
        guard var components = URLComponents(string: rawURL) else { return nil }
        let sizing = ["w": String(width), "q": "80", "fm": "jpg", "fit": "max"]
        var items = (components.queryItems ?? []).filter { sizing[$0.name] == nil }
        items += sizing.map { URLQueryItem(name: $0.key, value: $0.value) }
        components.queryItems = items
        return components.url
    }

    private static func largestCachedVariant(id: String, directory: URL) -> UIImage? {
        let files: [String]
        do {
            files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch {
            AppLogger.coverPhoto.error("Couldn't list the cover photo cache: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let widths = files.compactMap { name -> Int? in
            guard name.hasPrefix("\(id)_"), name.hasSuffix(".jpg") else { return nil }
            return Int(name.dropFirst(id.count + 1).dropLast(4))
        }
        guard let best = widths.max(),
              let data = readCachedFile(directory.appendingPathComponent("\(id)_\(best).jpg")) else {
            return nil
        }
        return decode(data, maxPixelSize: best)
    }

    /// A cached file's bytes, or nil if it isn't there. A file that exists but can't be read is logged.
    private static func readCachedFile(_ file: URL) -> Data? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            return try Data(contentsOf: file)
        } catch {
            AppLogger.coverPhoto.error("Couldn't read cached photo \(file.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Decoding

    /// Decodes off the main thread at no more than `maxPixelSize` on the long edge.
    private static func decode(_ data: Data, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
