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

    var showingMultiplePackers: Bool {
        didSet {
            UserDefaults.standard.set(showingMultiplePackers, forKey: "featureFlag_showingMultiplePackers")
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

    /// Reads the notifications flag straight from UserDefaults, so model and utility code can check it from any actor
    nonisolated static var notificationsEnabled: Bool {
        UserDefaults.standard.bool(forKey: "featureFlag_showingNotifications")
    }

    private init() {
        // Initialize from UserDefaults
        self.showingMultiplePackers = UserDefaults.standard.bool(forKey: "featureFlag_showingMultiplePackers")
        self.showingNotifications = UserDefaults.standard.bool(forKey: "featureFlag_showingNotifications")
        self.showingPackingEngine = UserDefaults.standard.bool(forKey: "featureFlag_showingPackingEngine")
        self.showingProfilePictures = UserDefaults.standard.bool(forKey: "featureFlag_showingProfilePictures")
    }
}
