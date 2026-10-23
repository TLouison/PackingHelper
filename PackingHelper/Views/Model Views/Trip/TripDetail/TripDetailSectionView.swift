//
//  TripDetailSectionView.swift
//  PackingHelper
//
//  Created by Todd Louison on 5/29/24.
//

import SwiftUI

struct TripDetailSectionView<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        TripDetailCustomSectionView {
            HStack {
                Text(title)
                    .font(.title)
                Spacer()
            }
        } content: {
            content
        }
    }
}

struct TripDetailCustomSectionView<Header: View, Content: View>: View {
    @Environment(\.tripDetailCardFillsHeight) private var fillsHeight

    @ViewBuilder let header: Header
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading) {
            header
            
            Divider()
            
            content
                .padding(.top)
        }
        .frame(maxHeight: fillsHeight ? .infinity : nil, alignment: .top)
        .roundedBox()
        .shaded()
    }
}

extension EnvironmentValues {
    /// Set by the fixed (non-scrolling) wide layouts so trip detail cards stretch to the height they're given
    @Entry var tripDetailCardFillsHeight: Bool = false
}

/// Stacks rows top-down and drops the ones that don't fit the proposed height, instead of scrolling or squashing.
/// Its ideal height is zero, so it only takes space a parent has left over.
struct FittingVStack: Layout {
    var spacing: CGFloat = 8
    /// Treat the first subview as a heading: hide it too unless at least one row fits after it
    var requiresRowAfterFirst: Bool = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        guard let height = proposal.height, height.isFinite else {
            return CGSize(width: width, height: 0)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)) }

        var fittingCount = 0
        var bottom = bounds.minY
        for size in sizes {
            guard bottom + size.height <= bounds.maxY else { break }
            bottom += size.height + spacing
            fittingCount += 1
        }
        if requiresRowAfterFirst && fittingCount < 2 {
            fittingCount = 0
        }

        var y = bounds.minY
        for (index, subview) in subviews.enumerated() {
            let size = sizes[index]
            if index < fittingCount {
                subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: size.height))
                y += size.height + spacing
            } else {
                // Park rows that don't fit out of bounds (the caller clips)
                subview.place(at: CGPoint(x: bounds.minX, y: bounds.maxY + 10_000), proposal: ProposedViewSize(width: bounds.width, height: size.height))
            }
        }
    }
}
