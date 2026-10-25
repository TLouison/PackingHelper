//
//  PlusSettingsSection.swift
//  PackingHelper
//
//  Top of Settings: a hero upsell card for free users, or a slim status row
//  that opens the Your Plus screen for subscribers.
//

import SwiftUI

struct PlusSettingsSection: View {
    @Environment(PurchaseManager.self) private var purchaseManager

    @State private var showingPaywall = false

    var body: some View {
        Section {
            if purchaseManager.isPlusActive {
                activeRow
            } else {
                PlusUpsellCard {
                    showingPaywall = true
                }
                .listRowBackground(PlusUpsellCard.background)
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PlusPaywallView()
        }
    }

    private var activeRow: some View {
        NavigationLink {
            PlusStatusView()
        } label: {
            LabeledContent {
                Text(statusText)
                    .foregroundStyle(isBillingIssue ? .orange : .secondary)
            } label: {
                Label {
                    Text("Packing Helper Plus")
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(defaultLinearGradient)
                }
            }
        }
        .accessibilityHint("Shows your plan and subscription options")
    }

    private var isBillingIssue: Bool {
        if case .billingIssue = PlusState(purchaseManager.plusEntitlement) { return true }
        return false
    }

    /// Short state for the row; the Your Plus screen has the details
    private var statusText: String {
        switch PlusState(purchaseManager.plusEntitlement) {
        case .renewing, .inactive: "Active"
        case .trial: "Trial"
        case .lifetime: "Lifetime"
        case .billingIssue: "Billing Issue"
        case .cancelled(let ends):
            ends.map { "Ends \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? "Ending"
        }
    }
}

private struct PlusUpsellCard: View {
    let onSeePlans: () -> Void

    static var background: some View {
        ZStack {
            Color(.secondarySystemGroupedBackground)
            LinearGradient(
                colors: [.accentColor.opacity(0.22), .purple.opacity(0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                plusSubscriptionIcon()
                    .font(.largeTitle)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Packing Helper Plus")
                        .font(.title3.bold())
                    Text("Pack smarter for every trip.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 12) {
                benefit(
                    icon: "sparkles",
                    title: "AI Packing Assistant",
                    detail: "Suggestions based on your destination, weather, and what you've already packed."
                )
                benefit(
                    icon: "magnifyingglass",
                    title: "Search Any Cover Photo",
                    detail: "Find the perfect photo for every trip instead of choosing from a preset selection."
                )
            }

            Button(action: onSeePlans) {
                Text("See Plans")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(.vertical, 8)
    }

    private func benefit(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(defaultLinearGradient)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview(traits: .sampleData) {
    Form {
        PlusSettingsSection()
    }
    .environment(PurchaseManager())
}
