//
//  PackingTips.swift
//  PackingHelper
//
//  TipKit tips that teach features where they're used (in place of onboarding explainer pages).
//  The Focus packing tips share a TipGroup in FocusPackingView, so only one shows at a time.
//  Each shows once (MaxDisplayCount), even if its popover is closed without the X.
//

import SwiftUI
import TipKit

/// On the chip rail's + while the trip has no sections
struct ApplyTemplateTip: Tip {
    @Parameter static var tripHasNoSections: Bool = false

    var title: Text { Text("Start with a Template") }
    var message: Text? { Text("Tap + to apply a template you pack every trip, or make a new section.") }
    var image: Image? { Image(systemName: "doc.on.doc") }

    /// Popovers closed by tapping outside aren't invalidated, so cap it at one showing
    var options: [any TipOption] { [Tips.MaxDisplayCount(1)] }

    var rules: [Rule] {
        #Rule(Self.$tripHasNoSections) { $0 }
    }
}

/// On the chip rail once there are sections to reorder
struct ReorderSectionsTip: Tip {
    @Parameter static var sectionCount: Int = 0

    var title: Text { Text("Reorder Sections") }
    var message: Text? { Text("Hold a section and drag it to change the order.") }
    var image: Image? { Image(systemName: "hand.draw") }

    /// Popovers closed by tapping outside aren't invalidated, so cap it at one showing
    var options: [any TipOption] { [Tips.MaxDisplayCount(1)] }

    var rules: [Rule] {
        #Rule(Self.$sectionCount) { $0 >= 2 }
    }
}

/// On the Templates tab's review banner (only shown when past trips have items to save)
struct SaveToTemplateTip: Tip {
    var title: Text { Text("Keep What You Added") }
    var message: Text? { Text("Items you added on past trips can be saved back to their templates for next time.") }
    var image: Image? { Image(systemName: "square.and.arrow.down.on.square") }

    /// Popovers closed by tapping outside aren't invalidated, so cap it at one showing
    var options: [any TipOption] { [Tips.MaxDisplayCount(1)] }
}
