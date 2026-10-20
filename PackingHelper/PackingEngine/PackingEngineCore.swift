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
    static func interpretItem(itemName: String) -> PackingRecommendationCategory {
        guard FeatureFlags.shared.showingPackingEngine else { return .other }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            let model = try ProductSuggestionModel(configuration: config)
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
