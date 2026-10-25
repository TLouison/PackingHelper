//
//  PlusStatusView.swift
//  PackingHelper
//
//  "Your Plus", pushed from Settings for subscribers: the plan and its state (renewing,
//  trial, cancelled, billing issue, lifetime), what's included, and subscription actions.
//  Uses Apple's own sheets for managing and refunds; Customer Center stays behind Contact
//  Support for troubleshooting.
//

import SwiftUI
import StoreKit
import RevenueCat
import RevenueCatUI

struct PlusStatusView: View {
    @Environment(PurchaseManager.self) private var purchaseManager

    @State private var product: StoreProduct?
    @State private var showingManageSubscriptions = false
    @State private var showingCustomerCenter = false
    @State private var showingPaywall = false
    @State private var isRestoring = false
    @State private var message: String?

    private var state: PlusState {
        PlusState(purchaseManager.plusEntitlement)
    }

    var body: some View {
        Form {
            Section {
                PlusStatusHeader(state: state, planName: planName, price: priceText, action: headerAction)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section("Included") {
                includedRow(
                    title: "AI Packing Assistant",
                    detail: "Open it from any trip's packing list",
                    systemImage: "sparkles"
                )
                includedRow(
                    title: "Search Any Cover Photo",
                    detail: "Search and Load More in the photo picker",
                    systemImage: "magnifyingglass"
                )
            }

            Section("Subscription") {
                if !state.isLifetime {
                    Button("Change or Cancel Plan") { showingManageSubscriptions = true }
                }
                Button {
                    restore()
                } label: {
                    HStack {
                        Text("Restore Purchases")
                        Spacer()
                        if isRestoring { ProgressView() }
                    }
                }
                .disabled(isRestoring)
                Button("Request a Refund") { requestRefund() }
            }

            Section("Help") {
                Button("Contact Support") { showingCustomerCenter = true }
            }
        }
        .navigationTitle("Your Plus")
        .navigationBarTitleDisplayMode(.inline)
        .manageSubscriptionsSheet(isPresented: $showingManageSubscriptions)
        .presentCustomerCenter(isPresented: $showingCustomerCenter)
        .sheet(isPresented: $showingPaywall) {
            PlusPaywallView()
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .task {
            await purchaseManager.refresh()
            product = await purchaseManager.plusProduct()
        }
        .onChange(of: showingManageSubscriptions) { _, isShowing in
            // Pick up a cancel or plan change made in Apple's sheet
            if !isShowing {
                Task { await purchaseManager.refresh() }
            }
        }
    }

    // MARK: - Plan

    /// "Yearly Plan" etc. from the product's billing period, or its ID until the product loads
    private var planName: String {
        if state.isLifetime { return "Lifetime" }
        if let unit = product?.subscriptionPeriod?.unit {
            switch unit {
            case .year: return "Yearly Plan"
            case .month: return "Monthly Plan"
            case .week: return "Weekly Plan"
            case .day: return "Daily Plan"
            }
        }
        let id = purchaseManager.plusEntitlement?.productIdentifier ?? ""
        if id.contains("year") { return "Yearly Plan" }
        if id.contains("month") { return "Monthly Plan" }
        return "Packing Helper Plus"
    }

    /// "$14.99/year"
    private var priceText: String? {
        guard let product else { return nil }
        guard let unit = product.subscriptionPeriod?.unit else { return product.localizedPriceString }
        let period = switch unit {
        case .year: "year"
        case .month: "month"
        case .week: "week"
        case .day: "day"
        }
        return "\(product.localizedPriceString)/\(period)"
    }

    /// The header's button: resubscribe or fix payment go through Apple's sheet; an ended plan reopens the paywall
    private var headerAction: (() -> Void)? {
        switch state {
        case .cancelled, .billingIssue: { showingManageSubscriptions = true }
        case .inactive: { showingPaywall = true }
        default: nil
        }
    }

    // MARK: - Rows

    private func includedRow(title: String, detail: String, systemImage: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(defaultLinearGradient)
        }
    }

    // MARK: - Actions

    private func restore() {
        isRestoring = true
        Task {
            defer { isRestoring = false }
            do {
                let isActive = try await purchaseManager.restore()
                message = isActive ? "Your purchases are restored." : "No purchases to restore were found."
            } catch {
                message = "Couldn't restore purchases. Please try again."
            }
        }
    }

    private func requestRefund() {
        Task {
            do {
                if try await purchaseManager.requestRefund() == .error {
                    message = "Couldn't open a refund request. Please try again."
                }
            } catch {
                message = "Couldn't open a refund request. Please try again."
            }
            await purchaseManager.refresh()
        }
    }
}

// MARK: - State

/// What the header says, from RevenueCat's entitlement
enum PlusState {
    case renewing(on: Date?, since: Date?)
    case trial(ends: Date?)
    case cancelled(ends: Date?)
    case billingIssue
    case lifetime(since: Date?)
    case inactive

    init(_ entitlement: EntitlementInfo?) {
        guard let entitlement, entitlement.isActive else {
            self = .inactive
            return
        }
        if entitlement.expirationDate == nil {
            self = .lifetime(since: entitlement.originalPurchaseDate)
        } else if entitlement.billingIssueDetectedAt != nil {
            self = .billingIssue
        } else if !entitlement.willRenew {
            self = .cancelled(ends: entitlement.expirationDate)
        } else if entitlement.periodType == .trial {
            self = .trial(ends: entitlement.expirationDate)
        } else {
            self = .renewing(on: entitlement.expirationDate, since: entitlement.originalPurchaseDate)
        }
    }

    var isLifetime: Bool {
        if case .lifetime = self { return true }
        return false
    }
}

// MARK: - Header

private struct PlusStatusHeader: View {
    let state: PlusState
    let planName: String
    let price: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kicker)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .opacity(0.85)

            Text(title)
                .font(.title2.bold())

            ForEach(details, id: \.self) { line in
                Text(line)
                    .font(.subheadline)
                    .opacity(0.95)
            }

            if let action, let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.glass)
                    .padding(.top, 6)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                background
                Image(systemName: "sparkles")
                    .font(.system(size: 96))
                    .foregroundStyle(.white.opacity(0.15))
                    .offset(x: 12, y: -12)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(.rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    private var kicker: String {
        switch state {
        case .renewing: "Packing Helper Plus"
        case .trial: "Free Trial"
        case .cancelled: "Cancelled"
        case .billingIssue: "Billing Issue"
        case .lifetime: "Lifetime"
        case .inactive: "Packing Helper Plus"
        }
    }

    private var title: String {
        switch state {
        case .renewing: planName
        case .trial(let ends): ends.map { "Trial ends \(Self.day($0))" } ?? "Free Trial"
        case .cancelled(let ends): ends.map { "Plus ends \(Self.day($0))" } ?? "Plus is ending"
        case .billingIssue: "Payment didn't go through"
        case .lifetime: "Plus is yours for good"
        case .inactive: "Plus isn't active"
        }
    }

    private var details: [String] {
        switch state {
        case .renewing(let on, let since):
            var lines: [String] = []
            if let on {
                lines.append(["Renews \(Self.day(on))", price].compactMap { $0 }.joined(separator: " · "))
            }
            if let since { lines.append("Member since \(Self.month(since))") }
            return lines
        case .trial:
            return [price.map { "Then \($0) · cancel anytime" } ?? "Cancel anytime"]
        case .cancelled:
            return ["You keep everything until then."]
        case .billingIssue:
            return ["Update your payment method to keep Plus."]
        case .lifetime(let since):
            return since.map { ["Purchased \(Self.month($0)) · no renewals"] } ?? ["No renewals"]
        case .inactive:
            return ["Subscribe again to get the AI assistant and photo search back."]
        }
    }

    private var actionTitle: String? {
        switch state {
        case .cancelled: "Resubscribe"
        case .billingIssue: "Update Payment"
        case .inactive: "See Plans"
        default: nil
        }
    }

    private var background: LinearGradient {
        let colors: [Color] = switch state {
        case .renewing, .lifetime: [.accentColor, .purple]
        case .trial: [.green, .teal]
        case .cancelled, .inactive: [.gray, Color(white: 0.35)]
        case .billingIssue: [.orange, .red]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private static func day(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private static func month(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }
}
