//
//  CoverPhotoImageView.swift
//  PackingHelper
//
//  Renders a cover photo aspect-filled around its focal point, with a color /
//  BlurHash placeholder while it loads. Fills whatever frame it's given, so use
//  it as a `.background` (or give it an explicit frame).
//

import SwiftUI

struct CoverPhotoImageView<Photo: CoverPhotoRepresentable>: View {
    let photo: Photo

    @Environment(\.displayScale) private var displayScale

    @State private var image: UIImage?
    @State private var loadedKey: CoverPhotoImageRequest?

    var body: some View {
        GeometryReader { geometry in
            let request = CoverPhotoImageRequest(photo: photo, pointSize: geometry.size, displayScale: displayScale)

            ZStack {
                placeholder

                if let image, loadedKey?.cacheKey == request?.cacheKey {
                    FocalPointImage(image: image, focalPoint: photo.focalPoint, zoom: photo.clampedZoom, size: geometry.size)
                        .transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .task(id: request) {
                await load(request)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var placeholder: some View {
        ZStack {
            photo.placeholderColor

            if let blurHash = photo.blurHash, let blurred = BlurHash.image(from: blurHash) {
                Image(uiImage: blurred)
                    .resizable()
                    .scaledToFill()
            }
        }
    }

    private func load(_ request: CoverPhotoImageRequest?) async {
        guard let request else { return }

        if let cached = CoverPhotoImageLoader.shared.cachedImage(for: request) {
            image = cached
            loadedKey = request
            return
        }

        let data = photo.source == .library ? photo.imageData : nil
        guard let loaded = await CoverPhotoImageLoader.shared.image(for: request, libraryData: data),
              !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: 0.25)) {
            image = loaded
            loadedKey = request
        }
    }
}

/// Aspect-fills `size` (then zooms by `zoom`), shifting the image so
/// `focalPoint` sits as close to the center as the overflow allows.
struct FocalPointImage: View {
    let image: UIImage
    let focalPoint: UnitPoint
    var zoom: Double = 1
    let size: CGSize

    var body: some View {
        let imageSize = image.size
        let fillScale = max(size.width / max(imageSize.width, 1), size.height / max(imageSize.height, 1))
        let scale = fillScale * zoom
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale

        let offsetX = clamp(size.width / 2 - focalPoint.x * scaledWidth, min: size.width - scaledWidth, max: 0)
        let offsetY = clamp(size.height / 2 - focalPoint.y * scaledHeight, min: size.height - scaledHeight, max: 0)

        Image(uiImage: image)
            .resizable()
            .frame(width: scaledWidth, height: scaledHeight)
            .offset(x: offsetX, y: offsetY)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
    }

    private func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, lower), upper)
    }
}
