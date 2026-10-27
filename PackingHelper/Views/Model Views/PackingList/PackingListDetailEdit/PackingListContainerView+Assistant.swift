//
//  PackingListContainerView+Assistant.swift
//  PackingHelper
//
//  The AI assistant side panel (regular width) and the open/close animation. At compact
//  width the assistant is a sheet instead (see `ActiveSheet.aiAssistant`).
//

import SwiftUI

extension PackingListContainerView {
    @ViewBuilder
    var assistantPanel: some View {
        if isAssistantPanelMounted {
            AIAssistantSheet(
                viewModel: assistantViewModel,
                users: users,
                targetUser: Bindable(editor).user,
                onClose: closeAssistantPanel
            )
        }
    }

    /// Reduce Motion swaps the panel slide for an instant change
    private var assistantPanelAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.45)
    }

    /// Slides the assistant in from the right, pushing the packed column off the left edge
    func openAssistantPanel() {
        isAssistantPanelMounted = true
        withAnimation(assistantPanelAnimation) {
            isShowingAssistantPanel = true
        }
    }

    func closeAssistantPanel() {
        withAnimation(assistantPanelAnimation) {
            isShowingAssistantPanel = false
        } completion: {
            // Reopened mid-slide: keep it mounted
            if !isShowingAssistantPanel {
                isAssistantPanelMounted = false
            }
        }
    }

    /// The Duo folded or unfolded: move an open conversation between the side panel and the sheet
    func handleSizeClassChange(to sizeClass: UserInterfaceSizeClass?) {
        // The panel only exists in the wide layout (e.g. the Duo was folded closed):
        // hand the open conversation over to the sheet instead of dropping it
        // (Another sheet already showing keeps the panel mounted rather than being replaced.)
        if sizeClass != .regular && isAssistantPanelMounted && activeSheet == nil {
            isShowingAssistantPanel = false
            isAssistantPanelMounted = false
            activeSheet = .aiAssistant
        } else if sizeClass == .regular && (activeSheet?.isAIAssistant ?? false) && context.isTrip {
            // Unfolded with the sheet open: move the conversation back into the side panel.
            // Shown in place (no slide) since the whole layout is already changing.
            activeSheet = nil
            isAssistantPanelMounted = true
            isShowingAssistantPanel = true
        }
    }
}
