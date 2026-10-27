//
//  PackingHelperPlusCTA.swift
//  PackingHelper
//
//  Created by Todd Louison on 7/16/24.
//

import SwiftUI

struct PackingHelperPlusCTA: View {
    enum CTAVersion {
        case small, tall, new
    }
    
//    @Environment(PurchaseManager.self) private var purchaseManager: PurchaseManager
    
    @State private var showingStoreSheet: Bool = false
    
    let headerText: String
    
    var version: CTAVersion = .small
    var showAfterPurchase: Bool = false
    
    // TODO: Re-enable these if useful
//    var smallCTA: some View {
//        Group {
//            if purchaseManager.isPlusActive {
//                if showAfterPurchase {
//                    // We want to show a "Thank You" after purchase
//                    HStack {
//                        plusLogoImage(size: 32)
//                        
//                        VStack {
//                            Text("Thanks for subscribing to")
//                            plusSubscriptionName()
//                            
//                            Button("View Your Subscription") {
//                                showingStoreSheet.toggle()
//                            }
//                            .padding(.horizontal)
//                            .padding(.vertical, 5)
//                            .background(.thickMaterial)
//                            .rounded()
//                        }
//                        .frame(maxWidth: .infinity)
//                    }
//                }
//            } else {
//                // The user is not subscribed
//                HStack {
//                    plusLogoImage(size: 32)
//                    
//                    VStack {
//                        plusSubscriptionHeader(header: headerText)
//                        
//                        Button("Learn More") {
//                            showingStoreSheet.toggle()
//                        }
//                        .padding(.horizontal)
//                        .padding(.vertical, 5)
//                        .background(.thickMaterial)
//                        .rounded()
//                    }
//                    .frame(maxWidth: .infinity)
//                }
//            }
//        }
//    }
//    
//    var tallCTA: some View {
//        Group {
//            if purchaseManager.isPlusActive {
//                if showAfterPurchase {
//                    VStack {
//                        plusLogoImage(size: 100)
//                        
//                        Spacer()
//                        
//                        Text("Thanks for subscribing to")
//                        plusSubscriptionName()
//                        
//                        Spacer()
//                        
//                        Button("View Your Subscription") {
//                            showingStoreSheet.toggle()
//                        }
//                        .padding(.horizontal)
//                        .padding(.vertical, 5)
//                        .background(.thickMaterial)
//                        .rounded()
//                    }
//                    .frame(maxWidth: .infinity)
//                }
//            } else {
//                VStack {
//                    plusLogoImage(size: 100)
//
//                    Spacer()
//                    
//                    VStack(spacing: 16) {
//                        plusSubscriptionHeader(header: headerText)
//                        
//                        plusSubscriptionBenefits()
//                    }
//                    
//                    Spacer()
//                    
//                    Button("Learn More") {
//                        showingStoreSheet.toggle()
//                    }
//                    .padding()
//                    .frame(maxWidth: .infinity)
//                    .background(.thickMaterial)
//                    .rounded()
//                    .contentShape(RoundedRectangle(cornerRadius: defaultCornerRadius))
//                }
//                .frame(maxWidth: .infinity)
//                .padding(.top, 50)
//            }
//        }
//        .frame(maxHeight: .infinity)
//    }
    
    var newCTA: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Upgrade to Premium", systemImage: "sparkles")
                    .font(.title2.bold())
                
                Text("Get unlimited trips, custom templates, and more")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                FeatureRow(icon: "infinity", text: "Create unlimited packing lists and trips")
                FeatureRow(icon: "square.stack", text: "Save custom templates for future trips")
                FeatureRow(icon: "person.2.fill", text: "Share lists with travel companions")
            }
            
            Button(action: {
                showingStoreSheet.toggle()
            }) {
                Text("View Plans")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    
    @ViewBuilder
    var ctaView: some View {
        switch version {
            // TODO: CTAs disabled until purchases figured out
//            case .small: smallCTA
//            case .tall: tallCTA
            case .small: EmptyView()
            case .tall: EmptyView()
            case .new: newCTA
        }
    }
    
    var body: some View {
        ctaView
            .roundedBox()
            .shaded()
            .overlay(
                RoundedRectangle(cornerRadius: defaultCornerRadius)
                    .strokeBorder(defaultLinearGradient)
            )
            .transition(.move(edge: .top))
            .padding()
            .sheet(isPresented: $showingStoreSheet) {
                PlusPaywallView()
            }
    }
}

struct SubscriptionCTAView: View {
   var body: some View {
       VStack(alignment: .leading, spacing: 24) {
           VStack(alignment: .leading, spacing: 8) {
               Label("Upgrade to Premium", systemImage: "sparkles")
                   .font(.title2.bold())
               
               Text("Get unlimited trips, custom templates, and more")
                   .foregroundStyle(.secondary)
                   .fixedSize(horizontal: false, vertical: true)
           }
           
           VStack(alignment: .leading, spacing: 8) {
               FeatureRow(icon: "infinity", text: "Create unlimited packing lists and trips")
               FeatureRow(icon: "square.stack", text: "Save custom templates for future trips")
               FeatureRow(icon: "person.2.fill", text: "Share lists with travel companions")
           }
           
           Button(action: {
               // Add navigation to subscription page
           }) {
               Text("View Plans")
                   .font(.headline)
                   .frame(maxWidth: .infinity)
                   .padding()
                   .background(.blue)
                   .foregroundStyle(.white)
                   .clipShape(RoundedRectangle(cornerRadius: 10))
           }
       }
       .padding(24)
       .background(.ultraThinMaterial)
       .overlay(
           RoundedRectangle(cornerRadius: 16)
               .stroke(defaultLinearGradient, lineWidth: 2)
       )
       .clipShape(RoundedRectangle(cornerRadius: 16))
       .shadow(radius: 8)
       .padding(.horizontal)
   }
}

private struct FeatureRow: View {
   let icon: String
   let text: String
   
   var body: some View {
       HStack(spacing: 12) {
           Image(systemName: icon)
               .font(.system(size: 16))
               .frame(width: 32, height: 32)
               .background(.blue.opacity(0.1))
               .foregroundStyle(.blue)
               .clipShape(Circle())
           
           Text(text)
               .font(.subheadline)
               .fixedSize(horizontal: false, vertical: true)
               .padding(.vertical, 6)  // Add vertical padding to match icon height
           
           Spacer(minLength: 0)
       }
   }
}


@available(iOS 18, *)
#Preview(traits: .sampleData) {
    PackingHelperPlusCTA(headerText: "Small CTA", version: .small)
}

@available(iOS 18, *)
#Preview(traits: .sampleData) {
    PackingHelperPlusCTA(headerText: "Tall CTA", version: .tall)
}
