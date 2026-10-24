//
//  WelcomeView.swift
//  PackingHelper
//
//  First launch: one welcome sheet. Continue creates the first packer (the app needs one to
//  show trips); the name is optional and defaults to "Me". Color and home base live in
//  Settings → Your Profile, and features are taught in context with tips instead of explainer pages.
//  Only Continue is pinned; the name field scrolls with the content so nothing sits under it.
//

import SwiftUI
import SwiftData

struct WelcomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    /// Developer Menu preview: Continue just closes the sheet without saving
    var isPreview = false

    @State private var name = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                header

                VStack(alignment: .leading, spacing: 28) {
                    WelcomeFeatureRow(
                        systemImage: "airplane.departure",
                        title: "Plan Every Trip",
                        detail: "Add where and when you're going, and see the forecast as the trip gets close."
                    )
                    WelcomeFeatureRow(
                        systemImage: "checklist",
                        title: "Pack Section by Section",
                        detail: "Split your packing into sections and tap items off as they go in the bag."
                    )
                    WelcomeFeatureRow(
                        systemImage: "doc.on.doc",
                        title: "Reuse Templates",
                        detail: "Save the lists you pack every time and apply them to any trip."
                    )
                }

                nameField
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaBar(edge: .bottom) { footer }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: suitcaseIcon)
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Welcome to Packing Helper")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Your Name", text: $name)
                .textContentType(.givenName)
                .submitLabel(.continue)
                .onSubmit(finish)
                .focused($isNameFocused)
                .padding(.horizontal, 16)
                .frame(minHeight: 50)
                .background(.fill.tertiary, in: .capsule)

            Text("Optional. You can change it later in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
        }
    }

    private var footer: some View {
        Button(action: finish) {
            Text("Continue")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: 520)
    }

    private func finish() {
        isNameFocused = false
        guard !isPreview else {
            dismiss()
            return
        }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = User(name: trimmed.isEmpty ? "Me" : trimmed, colorHex: Color.blue.toHex() ?? "#007AFF")
        modelContext.insert(user)
        try? modelContext.save()
        hasCompletedOnboarding = true
    }
}

private struct WelcomeFeatureRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(.tint)
                .frame(width: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview(traits: .sampleData) {
    WelcomeView(isPreview: true)
}
