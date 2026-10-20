//
//  AIChatBubbleView.swift
//  PackingHelper
//
//  A single chat message bubble (user or assistant) in the AI assistant sheet.
//

import SwiftUI

struct AIChatBubbleView: View {
    let role: AIAssistantViewModel.ChatEntry.Role
    let text: String

    private var isUser: Bool { role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }

            Text(text)
                .font(.body)
                .foregroundStyle(isUser ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

            if !isUser { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            Color.blue
        } else {
            Color(.secondarySystemBackground)
        }
    }
}
