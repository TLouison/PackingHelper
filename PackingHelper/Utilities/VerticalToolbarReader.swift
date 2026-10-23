//
//  VerticalToolbarReader.swift
//  PackingHelper
//

import SwiftUI

extension View {
    /// Tracks whether the toolbar is laid out vertically (iPhone Duo folded sidebar).
    /// Place items there with `.bottomBar` — top-bar placements stay in the horizontal bar.
    func readsVerticalToolbar(_ isVertical: Binding<Bool>) -> some View {
        modifier(VerticalToolbarReader(isVertical: isVertical))
    }
}

private struct VerticalToolbarReader: ViewModifier {
    @Binding var isVertical: Bool

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.modifier(ToolbarVerticalEdgeObserver(isVertical: $isVertical))
        } else {
            content
        }
    }
}

@available(iOS 27.1, *)
private struct ToolbarVerticalEdgeObserver: ViewModifier {
    @Environment(\.toolbarVerticalEdge) private var toolbarVerticalEdge
    @Binding var isVertical: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: toolbarVerticalEdge != nil, initial: true) { _, isPresent in
                isVertical = isPresent
            }
    }
}
