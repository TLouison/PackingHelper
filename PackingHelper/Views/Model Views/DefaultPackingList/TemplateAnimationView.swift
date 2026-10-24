import SwiftUI

/// Looping demo for the empty Templates tab: pick templates, they drop into the trip.
/// Drawn on a card with an arrow (not a button) so it reads as an illustration, not live controls.
/// Reduce Motion shows the still starting frame.
struct TemplateAnimationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let selectedColor = Color.accentColor

    // Per-icon state (5 icons)
    @State private var iconScales: [CGFloat] = Array(repeating: 1.0, count: 5)
    @State private var checkOpacities: [Double] = Array(repeating: 0.0, count: 5)
    @State private var checkScales: [CGFloat] = Array(repeating: 0.0, count: 5)
    @State private var iconOffsets: [CGSize] = Array(repeating: .zero, count: 5)
    @State private var iconOpacities: [Double] = Array(repeating: 1.0, count: 5)

    // Cursor
    @State private var cursorOffset: CGSize = CGSize(width: -86, height: -61)
    @State private var cursorOpacity: Double = 0

    // Arrow between the templates and the trip
    @State private var arrowScale: CGFloat = 1.0
    @State private var arrowHighlighted: Bool = false

    // Trip suitcase
    @State private var tripScale: CGFloat = 1.0

    // Layout constants (y offsets relative to ZStack center)
    private let iconsY: CGFloat = -75
    private let arrowY: CGFloat = -10
    private let suitcaseY: CGFloat = 70

    private let selectedIndices = [0, 2, 4]

    // Icon x offsets: [-100, -50, 0, 50, 100]
    private func iconX(_ i: Int) -> CGFloat { CGFloat(i - 2) * 50 }

    // Cursor position to point at a given icon (fingertip ≈ icon center)
    // hand.point.up.left.fill: fingertip is near top-left of bounds (~14pt from center)
    private func cursorOffsetForIcon(_ i: Int) -> CGSize {
        CGSize(width: iconX(i) + 14, height: iconsY + 14)
    }

    // Offset to fly icon[i] from its row position to the suitcase
    private func flyOffset(for i: Int) -> CGSize {
        CGSize(width: -iconX(i), height: suitcaseY - iconsY)
    }

    // Animate a single icon tap: scale bounce + check badge appear
    private func tapIcon(index: Int) async throws {
        withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
            iconScales[index] = 0.85
        }
        try await Task.sleep(for: .seconds(0.15))
        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
            iconScales[index] = 1.0
            checkOpacities[index] = 1.0
            checkScales[index] = 1.0
        }
        try await Task.sleep(for: .seconds(0.2))
    }

    private func runSequence() async throws {
        // Phase 1: cursor selects templates 0, 2, 4
        cursorOffset = cursorOffsetForIcon(0)
        withAnimation(.easeIn(duration: 0.25)) { cursorOpacity = 1 }
        try await Task.sleep(for: .seconds(0.3))

        for (i, idx) in selectedIndices.enumerated() {
            if i > 0 {
                withAnimation(.easeInOut(duration: 0.3)) {
                    cursorOffset = cursorOffsetForIcon(idx)
                }
                try await Task.sleep(for: .seconds(0.35))
            }
            try await tapIcon(index: idx)
        }

        // Phase 2: cursor leaves, arrow pulses toward the trip
        withAnimation(.easeOut(duration: 0.2)) { cursorOpacity = 0 }
        try await Task.sleep(for: .seconds(0.2))

        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
            arrowScale = 1.3
            arrowHighlighted = true
        }
        try await Task.sleep(for: .seconds(0.2))
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { arrowScale = 1.0 }

        // Phase 3: selected templates fly to suitcase
        withAnimation(.easeIn(duration: 0.5)) {
            for idx in selectedIndices {
                iconOffsets[idx] = flyOffset(for: idx)
                iconOpacities[idx] = 0
            }
        }
        try await Task.sleep(for: .seconds(0.35))

        withAnimation(.easeOut(duration: 0.2)) { arrowHighlighted = false }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { tripScale = 1.08 }
        try await Task.sleep(for: .seconds(0.2))
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { tripScale = 1.0 }
        try await Task.sleep(for: .seconds(0.2))

        // Phase 4: hold end state
        try await Task.sleep(for: .seconds(3.0))

        // Phase 5: reset — checks bounce off
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            for idx in selectedIndices {
                checkScales[idx] = 0
                checkOpacities[idx] = 0
            }
        }
        try await Task.sleep(for: .seconds(0.3))

        // Snap icons back to original position (invisible at this point)
        for idx in selectedIndices { iconOffsets[idx] = .zero }
        // Fade opacity back in with bounce
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            for idx in selectedIndices { iconOpacities[idx] = 1.0 }
        }
        try await Task.sleep(for: .seconds(0.5))
    }

    var body: some View {
        ZStack {
            // Template icons row
            HStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { index in
                    ZStack(alignment: .bottomTrailing) {
                        ZStack {
                            Circle()
                                .fill(selectedColor.opacity(0.15))
                                .frame(width: 40, height: 40)
                            Image(systemName: "list.bullet.rectangle.portrait")
                                .font(.system(size: 16))
                                .foregroundStyle(selectedColor)
                        }
                        .scaleEffect(iconScales[index])

                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.green)
                            .offset(x: 4, y: 4)
                            .opacity(checkOpacities[index])
                            .scaleEffect(checkScales[index])
                    }
                    .offset(iconOffsets[index])
                    .opacity(iconOpacities[index])
                }
            }
            .offset(y: iconsY)

            // Arrow from the templates to the trip
            Image(systemName: "arrow.down")
                .font(.title2.weight(.semibold))
                .foregroundStyle(selectedColor.opacity(arrowHighlighted ? 1 : 0.4))
                .scaleEffect(arrowScale)
                .offset(y: arrowY)

            // Suitcase (trip destination)
            ZStack {
                Circle()
                    .fill(selectedColor.opacity(0.15))
                    .frame(width: 70, height: 70)
                Image(systemName: "suitcase.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(selectedColor)
            }
            .scaleEffect(tripScale)
            .offset(y: suitcaseY)

            // Cursor overlay
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 28))
                .foregroundStyle(.primary)
                .opacity(cursorOpacity)
                .offset(cursorOffset)
        }
        .frame(height: 220)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
        .accessibilityHidden(true)
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                do { try await runSequence() } catch { break }
            }
        }
    }
}

#Preview {
    TemplateAnimationView()
        .padding()
}
