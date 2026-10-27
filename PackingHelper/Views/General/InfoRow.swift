//
//  InfoRow.swift
//  PackingHelper
//

import SwiftUI

/// Caption title on the leading side, detail view on the trailing side.
struct InfoRow<Detail: View>: View {
    let title: String
    let detail: Detail

    init(_ title: String, _ detail: Detail) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack {
            Text(title).font(.caption)
            Spacer()
            detail
        }
    }
}
