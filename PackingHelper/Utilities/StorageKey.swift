//
//  StorageKey.swift
//  PackingHelper
//

import Foundation

/// Key strings for `@AppStorage` and `UserDefaults`, in one place so a typo can't split a setting in two.
/// The values are what's already stored on devices, so don't change them.
enum StorageKey {
    static let appearanceMode = "appearanceMode"
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let autoCreateDefaultLists = "autoCreateDefaultLists"
    static let defaultTripCover = "defaultTripCover"
    static let packingStartPage = "packingStartPage"
    static let resetTipsOnLaunch = "resetTipsOnLaunch"
    static let workerURLOverride = "debug_workerURLOverride"

    // Feature flags
    static let showingMultiplePackers = "featureFlag_showingMultiplePackers"
    static let showingNotifications = "featureFlag_showingNotifications"
    static let showingPackingEngine = "featureFlag_showingPackingEngine"
    static let showingProfilePictures = "featureFlag_showingProfilePictures"
}
