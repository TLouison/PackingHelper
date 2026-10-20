//
//  AISuggestedItemChips.swift
//  PackingHelper
//
//  Renders an assistant reply's suggested items as tappable chips plus an
//  "Add all" affordance. Tapping a chip inserts the item into the user's list.
//

import SwiftUI

struct AISuggestedItemChips: View {
    let suggestions: [AISuggestedItem]
    let entryID: UUID
    let isAdded: (AISuggestedItem) -> Bool
    let onAdd: (AISuggestedItem) -> Void
    let onAddAll: () -> Void

    private var allAdded: Bool {
        suggestions.allSatisfy { isAdded($0) }
    }

    var body: some View {
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                AIFlowLayout(spacing: 8) {
                    ForEach(suggestions) { suggestion in
                        chip(for: suggestion)
                    }
                }

                if suggestions.count > 1 {
                    Button(action: onAddAll) {
                        Label(allAdded ? "All added" : "Add all", systemImage: allAdded ? "checkmark.circle.fill" : "plus.circle")
                            .font(.footnote.weight(.medium))
                    }
                    .disabled(allAdded)
                }
            }
        }
    }

    @ViewBuilder
    private func chip(for suggestion: AISuggestedItem) -> some View {
        let added = isAdded(suggestion)
        Button {
            withAnimation(.packingSpring) { onAdd(suggestion) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: added ? "checkmark" : categoryIcon(suggestion.category))
                    .font(.caption)
                VStack(alignment: .leading, spacing: 1) {
                    Text(suggestion.count > 1 ? "\(suggestion.name) ×\(suggestion.count)" : suggestion.name)
                        .font(.subheadline.weight(.medium))
                    if let accessoryFor = suggestion.accessoryFor, !accessoryFor.isEmpty {
                        Text("for \(accessoryFor)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(added ? Color.green.opacity(0.15) : Color(.secondarySystemBackground))
            .foregroundStyle(added ? Color.green : Color.primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(added)
    }

    private func categoryIcon(_ category: PackingRecommendationCategory) -> String {
        switch category {
        case .Clothing: return "tshirt"
        case .Electronics: return "bolt"
        case .Toiletries: return "drop"
        case .Task: return "checklist"
        case .other: return "shippingbox"
        }
    }
}

// MARK: - Flow layout

/// Minimal wrapping layout for variable-width chips.
struct AIFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var x: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                totalHeight += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            rows[rows.count - 1].append(subview)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
