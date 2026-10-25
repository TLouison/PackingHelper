//
//  CoverPhotoFocusView.swift
//  PackingHelper
//
//  Lets the user frame a cover photo. One fixed outline shows the area both the
//  trip card and the trip page keep, so whatever is inside it shows everywhere;
//  the photo moves (drag) and zooms (pinch) underneath it. Shown after every pick
//  and from "Adjust Focus".
//  Expects to be inside a NavigationStack.
//

import SwiftUI

struct CoverPhotoFocusView: View {
    @State var draft: CoverPhotoDraft
    let onCancel: () -> Void
    let onDone: (CoverPhotoDraft) -> Void

    @State private var image: UIImage?
    /// Focus when the current drag began; nil while not dragging.
    @State private var dragStartFocus: CGPoint?
    /// Zoom when the current pinch began; nil while not pinching.
    @State private var pinchStartZoom: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Drag and pinch the photo. Everything inside the frame shows on your trip.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            editor
                .frame(maxWidth: .infinity)
                .frame(height: 480)
                .clipShape(.rect(cornerRadius: 16))

            framingControls

            Spacer(minLength: 0)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Adjust Focus")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { onDone(draft) }
                    .fontWeight(.semibold)
            }
        }
        .task {
            await loadImage()
        }
    }

    // MARK: - Editor

    @ViewBuilder
    private var editor: some View {
        if let image {
            GeometryReader { geometry in
                let layout = FramingLayout(viewport: geometry.size, imageSize: image.size, zoom: draft.clampedZoom)
                let origin = layout.imageOrigin(focus: draft.focalPoint)

                ZStack(alignment: .topLeading) {
                    Color.black

                    Image(uiImage: image)
                        .resizable()
                        .frame(width: layout.imageSize.width, height: layout.imageSize.height)
                        .offset(x: origin.x, y: origin.y)

                    frameOverlay(layout)
                        .allowsHitTesting(false)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(dragGesture(layout))
                .simultaneousGesture(zoomGesture(layout))
                .accessibilityElement()
                .accessibilityLabel("Photo framing")
                .accessibilityValue("\(Int(draft.focalX * 100))% across, \(Int(draft.focalY * 100))% down, \(zoomText) zoom")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: setZoom(draft.zoom + 0.25, layout: layout)
                    case .decrement: setZoom(draft.zoom - 0.25, layout: layout)
                    @unknown default: break
                    }
                }
                .accessibilityAction(named: "Reset framing", resetFraming)
            }
        } else {
            Rectangle()
                .fill(draft.placeholderColor)
                .overlay { ProgressView() }
        }
    }

    /// Dims everything outside the area both crops keep and outlines it. The two crops are
    /// centered, so their overlap is the narrower width by the shorter height.
    private func frameOverlay(_ layout: FramingLayout) -> some View {
        let frame = layout.frameRect

        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.55)
                .mask {
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                        cutout(frame)
                    }
                    .compositingGroup()
                }

            outline(frame, style: StrokeStyle(lineWidth: 2))
                .foregroundStyle(.white)
        }
    }

    private func cutout(_ rect: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .blendMode(.destinationOut)
    }

    private func outline(_ rect: CGRect, style: StrokeStyle) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(style: style)
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .shadow(color: .black.opacity(0.4), radius: 2)
    }

    private var framingControls: some View {
        HStack {
            Label(zoomText, systemImage: "plus.magnifyingglass")
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.secondary)

            Spacer()

            Button("Reset", action: resetFraming)
                .disabled(isDefaultFraming)
        }
        .font(.subheadline)
    }

    // MARK: - Gestures

    private func dragGesture(_ layout: FramingLayout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragStartFocus ?? CGPoint(x: draft.focalX, y: draft.focalY)
                dragStartFocus = start
                // The photo follows the finger, so the focus moves the other way.
                let focus = CGPoint(
                    x: start.x - value.translation.width / layout.imageSize.width,
                    y: start.y - value.translation.height / layout.imageSize.height
                )
                setFocus(layout.clampedFocus(focus))
            }
            .onEnded { _ in
                dragStartFocus = nil
            }
    }

    private func zoomGesture(_ layout: FramingLayout) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStartZoom ?? draft.zoom
                pinchStartZoom = start
                setZoom(start * value.magnification, layout: layout)
            }
            .onEnded { _ in
                pinchStartZoom = nil
            }
    }

    // MARK: - State

    private var zoomText: String {
        draft.zoom.formatted(.number.precision(.fractionLength(1))) + "×"
    }

    private var isDefaultFraming: Bool {
        draft.focalX == 0.5 && draft.focalY == 0.5 && draft.zoom == 1
    }

    private func setFocus(_ focus: CGPoint) {
        draft.focalX = Double(focus.x)
        draft.focalY = Double(focus.y)
    }

    /// Zooms around the frame center, then pulls the focus back in so the
    /// frames stay covered when zooming out.
    private func setZoom(_ zoom: Double, layout: FramingLayout) {
        draft.zoom = min(max(zoom, 1), CoverPhotoDraft.maxZoom)
        let zoomed = layout.withZoom(draft.zoom)
        setFocus(zoomed.clampedFocus(CGPoint(x: draft.focalX, y: draft.focalY)))
    }

    private func resetFraming() {
        withAnimation(.snappy) {
            draft.focalX = 0.5
            draft.focalY = 0.5
            draft.zoom = 1
        }
    }

    private func loadImage() async {
        // Large enough to stay sharp when zoomed in the editor.
        guard let request = CoverPhotoImageRequest(
            photo: draft,
            pointSize: CGSize(width: 2000, height: 1),
            displayScale: 1
        ) else { return }
        let data = draft.source == .library ? draft.imageData : nil
        image = await CoverPhotoImageLoader.shared.image(for: request, libraryData: data)
    }
}

// MARK: - Layout

/// Geometry for the framing editor. At 1× each surface shows the largest crop
/// of its shape that fits the photo, centered on the focus. The editor draws
/// those crops as fixed frames and scales/moves the photo under them, so what's
/// inside a frame approximates what that surface will show.
struct FramingLayout {
    // Approximate shapes (width / height) of the two surfaces.
    static let cardAspectRatio: CGFloat = 300 / 440
    static let heroAspectRatio: CGFloat = 0.9
    static let padding: CGFloat = 20

    let viewport: CGSize
    let sourceSize: CGSize
    let zoom: CGFloat

    /// Photo size at 1× (the frames are inscribed in it).
    let baseImageSize: CGSize
    let heroFrame: CGRect
    let cardFrame: CGRect

    init(viewport: CGSize, imageSize: CGSize, zoom: Double) {
        self.viewport = viewport
        self.sourceSize = imageSize
        self.zoom = CGFloat(zoom)

        let aspect = max(imageSize.width, 1) / max(imageSize.height, 1)

        // Work in units where the photo is `aspect` wide and 1 tall.
        func inscribed(_ ratio: CGFloat) -> CGSize {
            ratio < aspect ? CGSize(width: ratio, height: 1) : CGSize(width: aspect, height: aspect / ratio)
        }
        let heroUnit = inscribed(Self.heroAspectRatio)
        let cardUnit = inscribed(Self.cardAspectRatio)
        let unionWidth = max(heroUnit.width, cardUnit.width)
        let unionHeight = max(heroUnit.height, cardUnit.height)

        let available = CGSize(
            width: max(viewport.width - Self.padding * 2, 1),
            height: max(viewport.height - Self.padding * 2, 1)
        )
        let unit = min(available.width / unionWidth, available.height / unionHeight)

        baseImageSize = CGSize(width: aspect * unit, height: unit)

        func centered(_ size: CGSize) -> CGRect {
            CGRect(
                x: (viewport.width - size.width * unit) / 2,
                y: (viewport.height - size.height * unit) / 2,
                width: size.width * unit,
                height: size.height * unit
            )
        }
        heroFrame = centered(heroUnit)
        cardFrame = centered(cardUnit)
    }

    func withZoom(_ zoom: Double) -> FramingLayout {
        FramingLayout(viewport: viewport, imageSize: sourceSize, zoom: zoom)
    }

    /// Displayed photo size at the current zoom.
    var imageSize: CGSize {
        CGSize(width: baseImageSize.width * zoom, height: baseImageSize.height * zoom)
    }

    /// Area both crops keep (the outlined frame); the photo must always fill it.
    /// Only this, not the wider crop: each surface clamps its own crop when drawn
    /// (`FocalPointImage`), so the frame can reach the photo's edges and the
    /// wider crop still contains it.
    var frameRect: CGRect { heroFrame.intersection(cardFrame) }

    /// Top-left of the photo so `focus` sits at the frame's center, limited so
    /// the photo never pulls away from the frame's edge.
    func imageOrigin(focus: UnitPoint) -> CGPoint {
        let size = imageSize
        let center = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let rect = frameRect
        let x = center.x - focus.x * size.width
        let y = center.y - focus.y * size.height
        return CGPoint(
            x: min(max(x, rect.maxX - size.width), rect.minX),
            y: min(max(y, rect.maxY - size.height), rect.minY)
        )
    }

    /// The focus that `imageOrigin` would actually display.
    func clampedFocus(_ focus: CGPoint) -> CGPoint {
        let origin = imageOrigin(focus: UnitPoint(x: focus.x, y: focus.y))
        let size = imageSize
        return CGPoint(
            x: (viewport.width / 2 - origin.x) / size.width,
            y: (viewport.height / 2 - origin.y) / size.height
        )
    }
}
