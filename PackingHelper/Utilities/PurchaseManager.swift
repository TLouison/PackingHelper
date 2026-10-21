//
//  PurchaseManager.swift
//  PackingHelper
//
//  Created by Todd Louison on 7/16/24.
//

import SwiftUI
import RevenueCat

let REVENUECAT_PUBLIC_API_KEY: String = {
    guard let key = Bundle.main.infoDictionary?["REVENUECAT_API_KEY"] as? String,
          !key.isEmpty else {
        assertionFailure("REVENUECAT_API_KEY not configured")
        return ""
    }
    return key
}()

/// Tracks the user's "PackingHelperPlus" entitlement via RevenueCat, which
/// completes purchases (Test Store in dev, App Store in prod). The local gate
/// mirrors RC's CustomerInfo — no direct StoreKit involvement.
@MainActor
@Observable
class PurchaseManager {
    static let entitlementID = "PackingHelperPlus"

    private(set) var isPlusActive = false

    private var observer: Task<Void, Never>?

    /// Begin observing RevenueCat entitlements. Call AFTER `Purchases.configure`
    /// (from the app's `.task`), never in `init` — the property is created
    /// before configuration runs.
    func start() async {
        if let info = try? await Purchases.shared.customerInfo() {
            apply(info)
        }
        observer?.cancel()
        observer = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.apply(info)
            }
        }
    }

    /// Re-fetch entitlements from RevenueCat, bypassing the SDK cache. The
    /// stream doesn't emit when an expiry date simply passes, so call this on
    /// foreground and whenever the Worker rejects us as unsubscribed.
    func refresh() async {
        if let info = try? await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent) {
            apply(info)
        }
    }

    private func apply(_ info: CustomerInfo) {
        isPlusActive = info.entitlements[Self.entitlementID]?.isActive == true
    }
}

extension PurchaseManager {
    var hasUnlockedPlus: Bool {
        isPlusActive
    }
}
