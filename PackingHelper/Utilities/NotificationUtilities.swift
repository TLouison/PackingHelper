//
//  NotificationUtilities.swift
//  PackingHelper
//
//  Created by Todd Louison on 10/23/23.
//

import Foundation
import UserNotifications
import OSLog

struct NotificationUtilities {
    static func getNotificationPermission() {
        guard FeatureFlags.notificationsEnabled else { return }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { success, error in
            if success {
                AppLogger.notifications.info("Notification permission granted")
            } else if let error = error {
                AppLogger.notifications.error("Notification permission error: \(error.localizedDescription)")
            }
        }
    }
}
