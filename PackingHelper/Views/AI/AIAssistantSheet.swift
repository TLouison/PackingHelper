//
//  AIAssistantSheet.swift
//  PackingHelper
//
//  The AI packing assistant chat. Ephemeral per presentation: conversation is
//  discarded on dismiss; added items are the durable artifact.
//

import SwiftUI
import SwiftData

struct AIAssistantSheet: View {
    let trip: Trip
    let users: [User]?
    @Binding var targetUser: User?
    @Binding var targetList: PackingList?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = AIAssistantViewModel()
    @FocusState private var composerFocused: Bool

    private var lists: [PackingList] { trip.lists ?? [] }
    private var hasMultiplePackers: Bool { (users?.count ?? 0) > 1 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                targetPicker
                Divider()
                conversation
                composer
            }
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
        .task {
            await viewModel.prepare(trip: trip, targetUser: targetUser, modelContext: modelContext)
            viewModel.targetList = targetList
        }
    }

    // MARK: - Target picker

    private var targetPicker: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(lists, id: \.id) { list in
                    Button {
                        targetList = list
                        viewModel.targetList = list
                    } label: {
                        if list.id == targetList?.id {
                            Label(list.name, systemImage: "checkmark")
                        } else {
                            Text(list.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet").font(.caption)
                    Text(targetList?.name ?? "Select List").fontWeight(.medium)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .opaqueGlassCapsule()
            }
            .disabled(lists.count <= 1)

            if hasMultiplePackers {
                UserPickerView(selectedUser: $targetUser, style: .menu, allowAll: false)
            }

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
                                AISuggestedItemChips(
                                    suggestions: entry.suggestions,
                                    entryID: entry.id,
                                    isAdded: { viewModel.isAdded($0, in: entry.id) },
                                    onAdd: { viewModel.add($0, from: entry.id) },
                                    onAddAll: { withAnimation(.packingSpring) { viewModel.addAll(from: entry.id) } }
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
