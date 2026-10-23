//
//  UnreadBadge.swift
//  PackingHelper
//
//  Red count badge in the style of an app icon's unread indicator.
//

import SwiftUI

struct UnreadBadge: View {
    let count: Int

    var body: some View {
        Text(count, format: .number)
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(.red, in: .capsule)
            .fixedSize()
    }
}

#Preview {
    HStack {
        UnreadBadge(count: 1)
        UnreadBadge(count: 12)
        UnreadBadge(count: 128)
    }
}
