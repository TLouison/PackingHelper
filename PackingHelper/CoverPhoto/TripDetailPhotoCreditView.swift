//
//  TripDetailPhotoCreditView.swift
//  PackingHelper
//
//  Unsplash attribution for a trip's cover photo, shown as a small caption
//  below the last card on the trip detail page. Only rendered for Unsplash photos.
//

import SwiftUI

struct TripDetailPhotoCreditView: View {
    let photo: TripCoverPhoto

    private var credit: AttributedString {
        var text = AttributedString("Photo by ")

        var name = AttributedString(photo.photographerName ?? "Unknown")
        if let profile = photo.photographerProfileURL {
            name.link = UnsplashService.referralURL(profile)
            name.underlineStyle = .single
        }
        text += name

        text += AttributedString(" on ")

        var unsplash = AttributedString("Unsplash")
        unsplash.link = UnsplashService.referralURL("https://unsplash.com")
        unsplash.underlineStyle = .single
        text += unsplash

        return text
    }

    var body: some View {
        Text(credit)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .tint(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}
