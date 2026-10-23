//
//  ColorUtilities.swift
//  PackingHelper
//
//  Created by Todd Louison on 6/26/24.
//

import SwiftUI
import UIKit

let supportedColors: [Color] = [Color.red, Color.pink, Color.orange, Color.yellow, Color.teal, Color.green, Color.blue, Color.indigo, Color.purple]

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 1.0

        let length = hexSanitized.count

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0

        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0

        } else {
            return nil
        }

        self.init(red: r, green: g, blue: b, opacity: a)
    }
    
    func toHex() -> String? {
            let uic = UIColor(self)
            guard let components = uic.cgColor.components, components.count >= 3 else {
                return nil
            }
            let r = Float(components[0])
            let g = Float(components[1])
            let b = Float(components[2])
            var a = Float(1.0)

            if components.count >= 4 {
                a = Float(components[3])
            }

            if a != Float(1.0) {
                return String(format: "%02lX%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255), lroundf(a * 255))
            } else {
                return String(format: "%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
            }
        }
}

// MARK: - Contrasting Text

extension View {
    /// Black or white foreground, whichever reads better on `background`.
    /// Resolved against the environment so light/dark variants of system colors are both handled.
    func foregroundStyle(contrastingWith background: Color) -> some View {
        modifier(ContrastingForeground(background: background))
    }
}

private struct ContrastingForeground: ViewModifier {
    @Environment(\.self) private var environment
    let background: Color

    func body(content: Content) -> some View {
        content.foregroundStyle(prefersDarkText ? Color.black : Color.white)
    }

    /// WCAG relative luminance (from linear sRGB); above ~0.18, black text has the higher contrast ratio
    private var prefersDarkText: Bool {
        let resolved = background.resolve(in: environment)
        let luminance = 0.2126 * resolved.linearRed
            + 0.7152 * resolved.linearGreen
            + 0.0722 * resolved.linearBlue
        return luminance > 0.179
    }
}
