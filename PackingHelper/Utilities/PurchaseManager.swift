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
    /// The Plus entitlement's details (plan, renewal, trial, billing issue) for the Your Plus screen
    private(set) var plusEntitlement: EntitlementInfo?

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

    /// Restore prior App Store purchases (Settings › Restore Purchases).
    /// Returns whether Plus is active afterward.
    @discardableResult
    func restore() async throws -> Bool {
        let info = try await Purchases.shared.restorePurchases()
        apply(info)
        return isPlusActive
    }

    /// Opens Apple's refund request sheet for the Plus purchase
    func requestRefund() async throws -> RefundRequestStatus {
        try await Purchases.shared.beginRefundRequest(forEntitlement: Self.entitlementID)
    }

    /// The App Store product behind Plus, for its price and billing period
    func plusProduct() async -> StoreProduct? {
        guard let id = plusEntitlement?.productIdentifier else { return nil }
        return await Purchases.shared.products([id]).first
    }

    private func apply(_ info: CustomerInfo) {
        let entitlement = info.entitlements[Self.entitlementID]
        isPlusActive = entitlement?.isActive == true
        plusEntitlement = entitlement
    }
}

extension PurchaseManager {
    var hasUnlockedPlus: Bool {
        isPlusActive
    }
}
