//
//  SectionCollapseStateManager.swift
//  PackingHelper
//
//  Created by Claude on 1/11/26.
//

import Foundation

/// Persists which sections are collapsed per trip, keyed by stable UUIDs
/// (`Trip.uuid` / `PackingList.collapseKey`) so state survives relaunches.
enum SectionCollapseStateManager {
    private static let userDefaultsKey = "sectionCollapseStates.v2"
    /// v1 keyed on `hashValue`, which Swift reseeds every launch, so it never matched again.
    private static let legacyUserDefaultsKey = "sectionCollapseStates"

    static func loadCollapsedSections(for tripId: UUID) -> Set<String> {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: legacyUserDefaultsKey)

        if let statesDict = defaults.dictionary(forKey: userDefaultsKey) as? [String: [String]],
           let collapsedIds = statesDict[tripId.uuidString] {
            return Set(collapsedIds)
        }

        return Set<String>()
    }

    static func saveCollapsedSections(_ sections: Set<String>, for tripId: UUID) {
        let defaults = UserDefaults.standard

        var statesDict = defaults.dictionary(forKey: userDefaultsKey) as? [String: [String]] ?? [:]
        statesDict[tripId.uuidString] = sections.isEmpty ? nil : Array(sections)

        defaults.set(statesDict, forKey: userDefaultsKey)
    }

    static func removeState(for tripId: UUID) {
        let defaults = UserDefaults.standard
        guard var statesDict = defaults.dictionary(forKey: userDefaultsKey) as? [String: [String]] else { return }
        statesDict[tripId.uuidString] = nil
        defaults.set(statesDict, forKey: userDefaultsKey)
    }
}
