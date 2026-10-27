//
//  UserColorPickerV.swift
//  PackingHelper
//
//  Created by Todd Louison on 6/26/24.
//

import SwiftUI
import OSLog

struct UserColorPicker: View {
    @Binding var selectedColor: Color
    
    @ViewBuilder private func colorButtonBase(color: Color, name: String) -> some View {
        Button {
            withAnimation(.snappy) {
                AppLogger.user.debug("Setting user color to \(color.description)")
                self.selectedColor = color
            }
        } label: {
            color
        }
        .buttonStyle(BorderlessButtonStyle())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .rounded()
        .shaded()
        .accessibilityLabel(name)
        .accessibilityAddTraits(color.toHex() == selectedColor.toHex() ? .isSelected : [])
    }
    
    @ViewBuilder private func colorButton(color: Color, name: String) -> some View {
        if color.toHex() == selectedColor.toHex() {
            colorButtonBase(color: color, name: name)
                .overlay {
                    RoundedRectangle(cornerRadius: defaultCornerRadius)
                        .stroke(Color.secondary, lineWidth: 4)
                }
        } else {
            colorButtonBase(color: color, name: name)
        }
    }
    var body: some View {
            Grid {
                GridRow {
                    colorButton(color: .red, name: "Red")
                    colorButton(color: .orange, name: "Orange")
                    colorButton(color: .yellow, name: "Yellow")
                    colorButton(color: .green, name: "Green")
                }
                GridRow {
                    colorButton(color: .teal, name: "Teal")
                    colorButton(color: .blue, name: "Blue")
                    colorButton(color: .indigo, name: "Indigo")
                    colorButton(color: .purple, name: "Purple")
                    
                }
            }
            .frame(maxWidth: 280)
    }
}

#Preview {
    @Previewable @State var selectedColor: Color = Color.accentColor
    UserColorPicker(selectedColor: $selectedColor)
}
