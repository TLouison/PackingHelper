//
//  CoverPhotoProcessing.swift
//  PackingHelper
//
//  Prepares photo-library picks for storage: downscaled, orientation baked in,
//  re-encoded as JPEG with no metadata (drops EXIF/GPS).
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

enum CoverPhotoProcessing {
    static let maxPixelSize = 2048
    static let jpegQuality = 0.8

    /// Returns nil if the data isn't a decodable image.
    static func preparedJPEG(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }

        // A bare CGImage carries no properties, so nothing from the original
        // file's metadata is written out.
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }

        let destinationOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: jpegQuality,
        ]
        CGImageDestinationAddImage(destination, image, destinationOptions as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
