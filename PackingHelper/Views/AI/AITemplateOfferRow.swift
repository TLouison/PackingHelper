//
//  AITemplateOfferRow.swift
//  PackingHelper
//
//  A template the assistant offers in a reply, shown above its item sections. Styled like a
//  suggestion row: + adds the whole template as a new list (skipping items already on the
//  trip), x hides it. Once added it says how many items were new.
//

import SwiftUI

struct AITemplateOfferRow: View {
    let offer: AIAssistantViewModel.TemplateOffer
    let status: AIAssistantViewModel.TemplateOfferStatus
    let onAdd: () -> Void
    let onDismiss: () -> Void

    private var isAvailable: Bool { status == .available }
    private var isAdded: Bool {
        if case .added = status { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 12) {
            tile

            VStack(alignment: .leading, spacing: 1) {
                Text(offer.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isAvailable ? .primary : .secondary)
                caption
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            trailingButtons
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(isAvailable || isAdded ? 1 : 0.5)
        .contextMenu {
            if isAvailable {
                Button("Add List", systemImage: "plus.circle", action: onAdd)
                Button("Not Now", systemImage: "xmark", action: onDismiss)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityActions {
            if isAvailable {
                Button("Add List", action: onAdd)
                Button("Not Now", action: onDismiss)
            }
        }
    }

    private var tile: some View {
        (isAdded ? Image(systemName: "checkmark") : glyph)
            .font(.subheadline.weight(.medium))
            .frame(width: 28, height: 28)
            .background(isAdded ? Color.green.opacity(0.15) : Color.accentColor.opacity(0.12))
            .foregroundStyle(isAdded ? Color.green : Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    /// The list's glyph; a plain packing template uses the Templates tab's suitcase
    private var glyph: Image {
        offer.kind.glyph(isDayOf: offer.isDayOf) ?? Image(systemName: suitcaseIcon)
    }

    @ViewBuilder
    private var caption: some View {
        switch status {
        case .available:
            let reason = offer.reason.isEmpty ? "Template" : "Template · \(offer.reason)"
            // The item count trails the reason when there's room for both on one line
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    Text(reason)
                    Text(itemCountText)
                        .foregroundStyle(.tertiary)
                }
                .lineLimit(1)
                Text(reason)
                    .lineLimit(2)
            }
        case .added(let newItems):
            Text(addedText(newItems))
        case .unavailable(let reason):
            Text(reason)
        }
    }

    @ViewBuilder
    private var trailingButtons: some View {
        switch status {
        case .available:
            HStack(spacing: 0) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Not Now")

                Button(action: onAdd) {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Add List")
            }
            .buttonStyle(.plain)
            .padding(.vertical, -8)
            .padding(.trailing, -10)
        case .added:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.green)
        case .unavailable:
            EmptyView()
        }
    }

    private var itemCountText: String {
        "\(offer.itemCount) item\(offer.itemCount == 1 ? "" : "s")"
    }

    private func addedText(_ newItems: Int) -> String {
        newItems == 0 ? "Already covered" : "Added · \(newItems) new item\(newItems == 1 ? "" : "s")"
    }

    private var accessibilityLabel: String {
        var parts = ["\(offer.name) template"]
        switch status {
        case .available:
            if !offer.reason.isEmpty { parts.append(offer.reason) }
            parts.append(itemCountText)
        case .added(let newItems):
            parts.append(addedText(newItems))
        case .unavailable(let reason):
            parts.append(reason)
        }
        return parts.joined(separator: ", ")
    }
}
