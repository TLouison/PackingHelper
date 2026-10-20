//
//  PlusPaywallView.swift
//  PackingHelper
//
//  Created by Todd Louison on 7/5/26.
//

import SwiftUI
import RevenueCatUI

/// RevenueCat remote-configured paywall. RevenueCat completes the purchase
/// (Test Store in dev, App Store in prod), so no observer-mode handlers are
/// needed — the bare `PaywallView` drives its own purchase/restore flow.
/// `PurchaseManager` picks up the resulting entitlement via CustomerInfo.
struct PlusPaywallView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PaywallView()
            .onPurchaseCompleted { _ in dismiss() }
            .onRestoreCompleted { _ in dismiss() }
    }
}
