//
//  LoggerUtilities.swift
//  PackingHelper
//
//  Created by Todd Louison on 6/29/24.
//

import Foundation
import OSLog

/// Centralized logging for PackingHelper app
enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.packinghelper"

    // Model loggers
    static let trip = Logger(subsystem: subsystem, category: "Trip")
    static let packingList = Logger(subsystem: subsystem, category: "PackingList")
    static let item = Logger(subsystem: subsystem, category: "Item")
    static let user = Logger(subsystem: subsystem, category: "User")
    static let location = Logger(subsystem: subsystem, category: "Location")

    // Feature loggers
    static let weather = Logger(subsystem: subsystem, category: "Weather")
    static let notifications = Logger(subsystem: subsystem, category: "Notifications")
    static let purchases = Logger(subsystem: subsystem, category: "Purchases")
    static let coverPhoto = Logger(subsystem: subsystem, category: "CoverPhoto")

    // UI loggers
    static let views = Logger(subsystem: subsystem, category: "Views")

    // General
    static let general = Logger(subsystem: subsystem, category: "General")
}
