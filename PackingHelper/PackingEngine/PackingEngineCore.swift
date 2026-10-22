//
//  PackingEngineCore.swift
//  PackingHelper
//
//  Created by Todd Louison on 10/16/23.
//

import Foundation
import CoreML

enum PackingRecommendationStatus {
    case result, empty
}

enum PackingRecommendationCategory: String, CaseIterable {
    case Clothing, Electronics, Toiletries, Task, other
}

struct PackingRecommendationResult {
    var status: PackingRecommendationStatus
    var category: PackingRecommendationCategory
    var item: String
    var count: Int
    var context: String
}

class PackingEngine {
    /// Loaded once on first use; compiling the CoreML model per call is expensive.
    private static let model: ProductSuggestionModel? = {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        return try? ProductSuggestionModel(configuration: config)
    }()

    static func interpretItem(itemName: String) -> PackingRecommendationCategory {
        guard FeatureFlags.shared.showingPackingEngine else { return .other }

        guard let model else { return .other }

        do {
            let output = try model.prediction(text: itemName)

            switch output.label {
            case "Electronics": return .Electronics
            case "Clothing": return .Clothing
            case "Toiletry": return .Toiletries
            default: return .other
            }
        } catch {
            return .other
        }
    }
}
