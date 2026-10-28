//
//  AIAssistantSheet.swift
//  PackingHelper
//
//  The AI packing assistant chat, for a trip or a template. The presenter owns the view model
//  so a conversation survives moving between the wide side panel and the sheet, and the view
//  model saves it, so closing the assistant keeps it until New Chat. Without Plus the chat is
//  replaced by a locked state and the paywall opens right away; buying reveals the chat.
//

import SwiftUI
import SwiftData

struct AIAssistantSheet: View {
    @Bindable var viewModel: AIAssistantViewModel
    let users: [User]?
    /// The packer suggestions go to (trip only)
    @Binding var targetUser: User?
    /// Set when embedded as a side panel (regular width) instead of presented as a sheet.
    /// The panel draws its own header and calls this from its close button.
    var onClose: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(PurchaseManager.self) private var purchaseManager
    @Environment(\.dismiss) private var dismiss

    @FocusState private var composerFocused: Bool
    @State private var showingPaywall = false

    /// Destinations for "Add to"; a template only has itself
    private var lists: [PackingList] { viewModel.context.trip?.lists ?? [] }
    private var hasMultiplePackers: Bool { !viewModel.isTemplate && (users?.count ?? 0) > 1 }

    var body: some View {
        Group {
            if let onClose {
                VStack(spacing: 0) {
                    panelHeader(onClose: onClose)
                    Divider()
                    chat
                }
                .background(Color(.systemBackground))
            } else {
                NavigationStack {
                    chat
                        .navigationTitle("AI Assistant")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    composerFocused = false
                                    dismiss()
                                }
                            }
                            if purchaseManager.isPlusActive {
                                ToolbarItem(placement: .primaryAction) {
                                    chatMenu
                                }
                            }
                        }
                }
            }
        }
        .task {
            // Check before the (possibly slow) prepare so the paywall opens immediately
            if !purchaseManager.isPlusActive {
                showingPaywall = true
            }
            await viewModel.prepare(modelContext: modelContext)
        }
        .onChange(of: targetUser?.persistentModelID, initial: true) {
            viewModel.targetUser = targetUser
            viewModel.refreshTemplateCandidates()
        }
        .onChange(of: viewModel.subscriptionLapsed) { _, lapsed in
            guard lapsed else { return }
            composerFocused = false
            Task {
                await purchaseManager.refresh()
                if purchaseManager.isPlusActive {
                    // RevenueCat still says active (the Worker's lookup failed): keep the error
                    // showing but let the next rejection try again
                    viewModel.subscriptionRestored()
                    viewModel.errorMessage = "Couldn't confirm your Plus subscription. Try again in a moment."
                } else {
                    showingPaywall = true
                }
            }
        }
        .onChange(of: purchaseManager.isPlusActive) { _, isActive in
            guard isActive else { return }
            viewModel.subscriptionRestored()
        }
        .sheet(isPresented: $showingPaywall) {
            PlusPaywallView()
        }
    }

    /// New Chat is the only way to clear the saved conversation
    private var chatMenu: some View {
        Menu {
            newChatButton
        } label: {
            Label("Chat Options", systemImage: "ellipsis")
        }
    }

    private var newChatButton: some View {
        Button("New Chat", systemImage: "square.and.pencil") {
            composerFocused = false
            withAnimation { viewModel.startNewChat() }
        }
        .disabled(viewModel.entries.isEmpty && viewModel.composerText.isEmpty)
    }

    /// Without Plus nothing of the conversation (including a saved one) shows
    @ViewBuilder
    private var chat: some View {
        if purchaseManager.isPlusActive {
            VStack(spacing: 0) {
                if hasMultiplePackers {
                    packerPicker
                    Divider()
                }
                conversation
                disclaimer
                composer
            }
        } else {
            lockedState
        }
    }

    // MARK: - Locked

    /// Shown instead of the chat until Plus is active (the paywall was closed without buying)
    private var lockedState: some View {
        ContentUnavailableView {
            Label("AI Assistant", systemImage: "sparkles")
        } description: {
            Text("The AI assistant comes with Packing Helper Plus.")
        } actions: {
            EmptyStateButton(title: "Unlock Plus", systemImage: "plus.circle") {
                showingPaywall = true
            }
        }
    }

    // MARK: - Panel header

    private func panelHeader(onClose: @escaping () -> Void) -> some View {
        HStack {
            Label("AI Assistant", systemImage: "sparkles")
                .font(.headline)
            Spacer()
            // A bare button, not the sheet's ⋯ menu, so New Chat is one visible tap
            if purchaseManager.isPlusActive {
                newChatButton
                    .labelStyle(.iconOnly)
                    .fontWeight(.semibold)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
            }
            Button {
                // Dismiss the keyboard before the panel animates away
                composerFocused = false
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Close AI Assistant")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Packer picker

    private var packerPicker: some View {
        HStack {
            UserPickerView(selectedUser: $targetUser, style: .menu, allowAll: false)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if viewModel.entries.isEmpty {
                        emptyState
                    }

                    ForEach(viewModel.entries) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            AIChatBubbleView(role: entry.role, text: entry.text)

                            if entry.role == .assistant, let offer = entry.template, offer.state != .dismissed {
                                AITemplateOfferRow(
                                    offer: offer,
                                    status: viewModel.templateOfferStatus(for: offer),
                                    onAdd: { withAnimation(.packingSpring) { viewModel.addTemplate(from: entry.id) } },
                                    onDismiss: { withAnimation(.packingSpring) { viewModel.dismissTemplate(from: entry.id) } }
                                )
                                .transition(.opacity)
                            }

                            if entry.role == .assistant {
                                AISuggestedItemList(
                                    suggestions: entry.suggestions,
                                    lists: lists,
                                    isAdded: { viewModel.isAdded($0, in: entry.id) },
                                    destination: { viewModel.destination(for: $0) },
                                    onAdd: { suggestion, list in viewModel.add(suggestion, from: entry.id, to: list) },
                                    onAddAll: { items, list in withAnimation(.packingSpring) { viewModel.addAll(items, from: entry.id, to: list) } }
                                )
                            }
                        }
                        .id(entry.id)
                    }

                    if viewModel.isLoading {
                        typingIndicator
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.entries.count) {
                if let last = viewModel.entries.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let template = viewModel.context.singleList {
                Label("Build this template", systemImage: "sparkles")
                    .font(.headline)
                Text("Tell me what this list is for, like a beach weekend or work travel, and I'll suggest a solid set of items to start from.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                starterButtons([
                    template.items?.isEmpty ?? true
                        ? "Suggest a starting set for \(template.name)"
                        : "What's missing from \(template.name)?"
                ])
            } else {
                Label("Ask about your trip", systemImage: "sparkles")
                    .font(.headline)
                Text("Describe your plans, like activities or what you're bringing, and I'll suggest what to pack, including easy-to-forget accessories.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                starterButtons([
                    "What am I missing?",
                    "What should I do before I leave?"
                ] + (viewModel.hasTemplateCandidates ? ["Do any of my templates fit?"] : []))
            }
        }
        .padding(.top, 24)
    }

    /// One-tap first messages
    private func starterButtons(_ prompts: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(prompts, id: \.self) { prompt in
                Button(prompt) {
                    composerFocused = false
                    Task { await viewModel.send(prompt) }
                }
                .font(.subheadline)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
        .disabled(viewModel.composerDisabled)
        .padding(.top, 8)
    }

    private var typingIndicator: some View {
        TypingIndicator()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityElement()
            .accessibilityLabel("AI Assistant is typing")
    }

    /// Sits on the chat background, just above the composer
    private var disclaimer: some View {
        Text("AI can make mistakes. Check suggestions before you rely on them.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            .padding(.vertical, 6)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 6) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if viewModel.remaining == 0 {
                limitReachedBar
            } else {
                inputBar
                if let remaining = viewModel.remaining, remaining < 10 {
                    Text("\(remaining) message\(remaining == 1 ? "" : "s") left this month")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(viewModel.isTemplate ? "What is this list for?" : "Describe your plans…", text: $viewModel.composerText, axis: .vertical)
                .lineLimit(1...4)
                .focused($composerFocused)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onSubmit(submit)

            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(viewModel.composerDisabled || viewModel.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var limitReachedBar: some View {
        VStack(spacing: 2) {
            Text("You've used this month's AI messages.")
                .font(.subheadline.weight(.medium))
            if let resetsAt = viewModel.resetsAt {
                Text("Resets \(resetsAt.formatted(.dateTime.month().day()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func submit() {
        Task { await viewModel.send() }
    }
}

/// Three dots that swell and shrink one after another, like the other person typing.
/// Reduce Motion fades them instead of scaling.
private struct TypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let dotSize: CGFloat = 7
    private let period: Double = 1.2
    /// Each dot trails the one before it by this fraction of the cycle
    private let stagger: Double = 0.18

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    let pulse = pulse(at: time, index: index)
                    Circle()
                        .fill(.secondary)
                        .frame(width: dotSize, height: dotSize)
                        .scaleEffect(reduceMotion ? 1 : 0.6 + 0.4 * pulse)
                        .opacity(0.4 + 0.6 * pulse)
                }
            }
        }
    }

    /// 0...1, peaking once per cycle; dots rest small between peaks
    private func pulse(at time: TimeInterval, index: Int) -> Double {
        let phase = (time / period - Double(index) * stagger).truncatingRemainder(dividingBy: 1)
        let wrapped = phase < 0 ? phase + 1 : phase
        // Swell over the first 60% of the cycle, rest for the remainder
        guard wrapped < 0.6 else { return 0 }
        return sin(wrapped / 0.6 * .pi)
    }
}
