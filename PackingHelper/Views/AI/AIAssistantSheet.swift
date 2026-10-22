//
//  AIAssistantSheet.swift
//  PackingHelper
//
//  The AI packing assistant chat. The presenter owns the view model so a conversation
//  survives moving between the wide side panel and the sheet; it is discarded when the
//  assistant is closed. Added items are the durable artifact.
//

import SwiftUI
import SwiftData

struct AIAssistantSheet: View {
    @Bindable var viewModel: AIAssistantViewModel
    let trip: Trip
    let users: [User]?
    @Binding var targetUser: User?
    /// Called after the Worker reports no active subscription and entitlements
    /// have been refreshed; the presenter should close this and show the paywall.
    var onSubscriptionLapsed: () -> Void = {}
    /// Set when embedded as a side panel (regular width) instead of presented as a sheet.
    /// The panel draws its own header and calls this from its close button.
    var onClose: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(PurchaseManager.self) private var purchaseManager
    @Environment(\.dismiss) private var dismiss

    @FocusState private var composerFocused: Bool

    private var lists: [PackingList] { trip.lists ?? [] }
    private var hasMultiplePackers: Bool { (users?.count ?? 0) > 1 }

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
                        }
                }
            }
        }
        .task {
            await viewModel.prepare(trip: trip, targetUser: targetUser, modelContext: modelContext)
        }
        .onChange(of: viewModel.subscriptionLapsed) { _, lapsed in
            guard lapsed else { return }
            composerFocused = false
            Task {
                await purchaseManager.refresh()
                onSubscriptionLapsed()
            }
        }
    }

    private var chat: some View {
        VStack(spacing: 0) {
            if hasMultiplePackers {
                packerPicker
                Divider()
            }
            conversation
            composer
        }
    }

    // MARK: - Panel header

    private func panelHeader(onClose: @escaping () -> Void) -> some View {
        HStack {
            Label("AI Assistant", systemImage: "sparkles")
                .font(.headline)
            Spacer()
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

                            if entry.role == .assistant {
                                AISuggestedItemList(
                                    suggestions: entry.suggestions,
                                    lists: lists,
                                    isAdded: { viewModel.isAdded($0, in: entry.id) },
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
            Label("Ask about your trip", systemImage: "sparkles")
                .font(.headline)
            Text("Describe your plans — activities, what you're bringing — and I'll suggest what to pack, including easy-to-forget accessories.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 24)
    }

    private var typingIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { _ in
                Circle().fill(.secondary).frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
            TextField("Describe your plans…", text: $viewModel.composerText, axis: .vertical)
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
