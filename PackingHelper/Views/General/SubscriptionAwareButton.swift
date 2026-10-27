//
//  SubscriptionAwareButton.swift
//  PackingHelper
//
//  Created by Todd Louison on 7/16/24.
//

import SwiftUI
import OSLog

struct SubscriptionAwareButton<Label: View>: View {
    @State private var isShowingSubscriptionStoreSheet = false
    
    var localLimitMet: Bool
    
    var paidAction: () -> Void
    @ViewBuilder let label: () -> Label
    
    // Temporary force allow until purchases is figured out
    var canPerformAction: Bool {
        true
    }
    
    var body: some View {
        Button {
            withAnimation {
                if canPerformAction {
                    AppLogger.purchases.debug("User has permission, running action")
                    paidAction()
                } else {
                    AppLogger.purchases.info("User is not subscribed, showing subscription page")
                }
            }
        } label: {
            label()
                .labelStyle(.iconOnly)
        }
        .disabled(!canPerformAction)
        .sheet(isPresented: $isShowingSubscriptionStoreSheet) {
            PlusPaywallView()
        }
    }
}

#Preview {
    VStack(spacing: 32) {
        SubscriptionAwareButton(localLimitMet: true) {
            AppLogger.purchases.debug("Preview button tapped")
        } label: {
            Label("Print Hello", systemImage: "globe")
                .labelStyle(.iconOnly)
        }

        SubscriptionAwareButton(localLimitMet: false) {
            AppLogger.purchases.debug("Preview button tapped")
        } label: {
            Label("Print Hello", systemImage: "globe")
                .labelStyle(.iconOnly)
        }
    }
}
