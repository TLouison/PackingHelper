//
//  ViewModifierUtilities.swift
//  PackingHelper
//
//  Created by Todd Louison on 10/18/23.
//

import SwiftUI
import UIKit

/// Content card. Uses a standard material: HIG reserves Liquid Glass for controls and
/// navigation floating above content, while materials separate content from content.
struct Box: ViewModifier {
    let background: Material
    
    func body(content: Content) -> some View {
        content
            .padding()
            .background(background, in: .rect(cornerRadius: defaultCornerRadius))
    }
}

/// Glass card for content that floats over imagery (cover photo or map), like a trip card's info bar
struct GlassBox: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .glassEffect(in: .rect(cornerRadius: defaultCornerRadius))
    }
}

struct Rounded: ViewModifier {
    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: defaultCornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: defaultCornerRadius))
    }
}

struct Shaded: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
            .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 0.25)
    }
}

struct BorderGradient: ViewModifier {
    let width: CGFloat
    
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: defaultCornerRadius)
                    .strokeBorder(defaultLinearGradient, lineWidth: width)
            )
    }
}

// MARK: - OpaqueBox (less-transparent glass for floating input bar)

struct OpaqueBox: ViewModifier {
    let background: Material

    func body(content: Content) -> some View {
        content
            .padding()
            .background(Color(UIColor.systemBackground).opacity(0.5), in: RoundedRectangle(cornerRadius: defaultCornerRadius))
            .glassEffect(in: .rect(cornerRadius: defaultCornerRadius))
    }
}

// MARK: - OpaqueGlassCapsule (less-transparent glass for chip/pill shapes)

struct OpaqueGlassCapsule: ViewModifier {
    let background: Material

    func body(content: Content) -> some View {
        content
            .background(Color(UIColor.systemBackground).opacity(0.3), in: Capsule())
            .glassEffect(in: .capsule)
    }
}

extension View {
    func rounded()
        -> some View {
            modifier(Rounded())
      }

    func box(background: Material = .thinMaterial) -> some View {
        modifier(Box(background: background))
    }

    func roundedBox(background: Material = .thinMaterial) -> some View {
        modifier(Box(background: background)).modifier(Rounded())
    }

    func glassRoundedBox() -> some View {
        modifier(GlassBox()).modifier(Rounded())
    }

    func opaqueRoundedBox(background: Material = .thinMaterial) -> some View {
        modifier(OpaqueBox(background: background)).modifier(Rounded())
    }

    func opaqueGlassCapsule(background: Material = .thinMaterial) -> some View {
        modifier(OpaqueGlassCapsule(background: background))
    }

    func shaded() -> some View {
        modifier(Shaded())
    }

    func borderGradient(width: CGFloat = 1) -> some View {
        modifier(BorderGradient(width: width))
    }
}
