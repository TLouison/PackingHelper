//
//  FeatureFlags.swift
//  PackingHelper
//
//  Created by Todd Louison on 10/22/23.
//

import Foundation
import SwiftUI

@Observable
class FeatureFlags {
    static let shared = FeatureFlags()

    var showingRecommendations: Bool {
        didSet {
            UserDefaults.standard.set(showingRecommendations, forKey: "featureFlag_showingRecommendations")
        }
    }

    var showingMultiplePackers: Bool {
        didSet {
            UserDefaults.standard.set(showingMultiplePackers, forKey: "featureFlag_showingMultiplePackers")
        }
    }

    var showingSubscription: Bool {
        didSet {
            UserDefaults.standard.set(showingSubscription, forKey: "featureFlag_showingSubscription")
        }
    }

    var showingNotifications: Bool {
        didSet {
            UserDefaults.standard.set(showingNotifications, forKey: "featureFlag_showingNotifications")
        }
    }

    var showingPackingEngine: Bool {
        didSet {
            UserDefaults.standard.set(showingPackingEngine, forKey: "featureFlag_showingPackingEngine")
        }
    }

    var showingProfilePictures: Bool {
        didSet {
            UserDefaults.standard.set(showingProfilePictures, forKey: "featureFlag_showingProfilePictures")
        }
    }

    var showingUnsplashPhotos: Bool {
        didSet {
            UserDefaults.standard.set(showingUnsplashPhotos, forKey: "featureFlag_showingUnsplashPhotos")
        }
    }

    private init() {
        // Initialize from UserDefaults
        self.showingRecommendations = UserDefaults.standard.bool(forKey: "featureFlag_showingRecommendations")
        self.showingMultiplePackers = UserDefaults.standard.bool(forKey: "featureFlag_showingMultiplePackers")
        self.showingSubscription = UserDefaults.standard.bool(forKey: "featureFlag_showingSubscription")
        self.showingNotifications = UserDefaults.standard.bool(forKey: "featureFlag_showingNotifications")
        self.showingPackingEngine = UserDefaults.standard.bool(forKey: "featureFlag_showingPackingEngine")
        self.showingProfilePictures = UserDefaults.standard.bool(forKey: "featureFlag_showingProfilePictures")
        self.showingUnsplashPhotos = UserDefaults.standard.bool(forKey: "featureFlag_showingUnsplashPhotos")
    }
}
