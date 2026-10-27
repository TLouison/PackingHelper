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
            UserDefaults.standard.set(showingMultiplePackers, forKey: StorageKey.showingMultiplePackers)
        }
    }

    var showingNotifications: Bool {
        didSet {
            UserDefaults.standard.set(showingNotifications, forKey: StorageKey.showingNotifications)
        }
    }

    var showingPackingEngine: Bool {
        didSet {
            UserDefaults.standard.set(showingPackingEngine, forKey: StorageKey.showingPackingEngine)
        }
    }

    var showingProfilePictures: Bool {
        didSet {
            UserDefaults.standard.set(showingProfilePictures, forKey: StorageKey.showingProfilePictures)
        }
    }

    /// Reads the notifications flag straight from UserDefaults, so model and utility code can check it from any actor
    nonisolated static var notificationsEnabled: Bool {
        UserDefaults.standard.bool(forKey: "featureFlag_showingNotifications")
    }

    private init() {
        // Initialize from UserDefaults
        self.showingMultiplePackers = UserDefaults.standard.bool(forKey: StorageKey.showingMultiplePackers)
        self.showingNotifications = UserDefaults.standard.bool(forKey: StorageKey.showingNotifications)
        self.showingPackingEngine = UserDefaults.standard.bool(forKey: StorageKey.showingPackingEngine)
        self.showingProfilePictures = UserDefaults.standard.bool(forKey: StorageKey.showingProfilePictures)
    }
}
