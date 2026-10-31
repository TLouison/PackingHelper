//
//  ListNameLabel.swift
//  PackingHelper
//
//  A list's name, led by a small secondary glyph for task lists.
//  Packing lists show the name alone. Takes its font from the environment.
//

import SwiftUI

struct ListNameLabel: View {
    let name: String
    let kind: ListKind

    init(list: PackingList) {
        self.init(name: list.name, kind: list.kind)
    }

    init(name: String, kind: ListKind) {
        self.name = name
        self.kind = kind
    }

    var body: some View {
        // Centered, not baseline-aligned: a small glyph on the baseline sits low beside the name
        HStack(spacing: 4) {
            ListKindGlyph(kind: kind)
            Text(name)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The list type's glyph on its own, at a fixed small size (caption, scales with Dynamic Type).
/// Draws nothing for packing lists.
struct ListKindGlyph: View {
    let kind: ListKind

    init(kind: ListKind) {
        self.kind = kind
    }

    init(list: PackingList) {
        self.init(kind: list.kind)
    }

    /// Fixed slot so names start at the same spot whatever the glyph's own width
    @ScaledMetric(relativeTo: .caption) private var slotWidth: CGFloat = 18

    var body: some View {
        if let glyph = kind.glyph {
            // Own small font, not the label's: a large-title glyph crowds the name
            glyph
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: slotWidth)
                .accessibilityLabel(kind.name)
        }
    }
}

/// A list in a menu (Move To and similar): its glyph as the item's icon, packing lists text only
struct ListMenuLabel: View {
    let list: PackingList

    var body: some View {
        if let glyph = list.glyph {
            Label { Text(list.name) } icon: { glyph }
        } else {
            Text(list.name)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(ListKind.allCases) { kind in
            ListNameLabel(name: kind.name, kind: kind)
        }
    }
    .font(.title3.bold())
}
