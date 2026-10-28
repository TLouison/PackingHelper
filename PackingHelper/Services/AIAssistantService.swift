//
//  AIAssistantService.swift
//  PackingHelper
//
//  Networking for the AI packing assistant. Talks to the PackingHelperWorkers
//  Cloudflare Worker (which holds the Anthropic key, verifies the subscriber,
//  and meters usage). Keep these DTOs in sync with the Worker's HTTP contract
//  (PackingHelperWorkers/README.md).
//

import Foundation

// MARK: - Request DTOs

struct AIAssistantRequest: Encodable {
    let rcAppUserId: String
    let mode: Mode
    /// Set in `.trip` mode
    let tripContext: AITripContext?
    /// Set in `.template` mode
    let templateContext: AITemplateContext?
    let messages: [AIChatMessageDTO]

    enum Mode: String, Encodable {
        /// Fill gaps in a trip's lists
        case trip
        /// Build a reusable starting point for a template list
        case template
    }
}

struct AITripContext: Encodable {
    let tripName: String
    let destinationName: String
    /// For the season (hemisphere, tropics); nil when the destination has no coordinates
    let destinationLatitude: Double?
    let originName: String?
    let startDate: String   // yyyy-MM-dd
    let endDate: String     // yyyy-MM-dd
    let durationDays: Int
    let tripType: String
    let accommodation: String
    let packerCount: Int
    /// Every list on the trip, so the model can say which one each suggestion goes on.
    /// Names hint at plans ("Ski Gear"); items are for dedupe and accessory reasoning
    let lists: [AITripList]
    /// What the trip's other packers are bringing, so shared items aren't doubled up
    let otherPackersItems: [String]
    /// The packer's most similar other trips (`AIPastTripsBuilder`)
    let pastTrips: [AIPastTrip]
    let weather: AIWeatherContext?  // nil → omitted (synthesized encoder uses encodeIfPresent)
}

struct AITripList: Encodable {
    /// A short per-request id ("L1", "L2", …) that suggestions name their list with
    /// (`AISuggestedItem.listId`). Short because the model writes it once per suggestion, and a
    /// UUID costs ~25 output tokens each time
    let id: String
    /// The list `id` stands for; not sent. The view model swaps it in when the reply arrives
    let listUUID: UUID
    let name: String
    let kind: String  // "packing" | "tasks"
    let isDayOf: Bool
    let isDefault: Bool
    /// The template it was applied from; nil for lists made on this trip
    let fromTemplate: String?
    /// The packer's items plus unassigned ones on this list, packed or not
    let items: [String]

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, isDayOf, isDefault, fromTemplate, items
    }
}

struct AITemplateContext: Encodable {
    let name: String
    let listKind: String  // "packing" | "tasks"
    let isDayOf: Bool
    /// Item counts become the trip's length when applied, so counts don't matter
    let countAsDays: Bool
    let existingItems: [String]
    /// Trips this template was used on first, then recent ones (`AIPastTripsBuilder`)
    let pastTrips: [AIPastTrip]
}

/// What a packer brought on another trip, minus items already on the current trip or template
struct AIPastTrip: Encodable {
    let name: String
    let destinationName: String
    let month: String  // yyyy-MM
    let durationDays: Int
    let tripType: String
    let accommodation: String
    let lists: [AIPastTripList]
}

struct AIPastTripList: Encodable {
    let name: String
    let kind: String  // "packing" | "tasks"
    /// The template it was applied from; nil for lists made on that trip
    let fromTemplate: String?
    let items: [String]
}

struct AIWeatherContext: Encodable {
    let currentTempC: Double
    let daily: [AIDailyWeather]
}

struct AIDailyWeather: Encodable {
    let day: String  // yyyy-MM-dd
    let highC: Double
    let lowC: Double
    let condition: String
}

struct AIChatMessageDTO: Codable {
    let role: String  // "user" | "assistant"
    let content: String
}

// MARK: - Response DTOs

struct AIAssistantResponse: Decodable {
    let message: String
    let items: [AISuggestedItem]
    let remaining: Int
}

/// Decoded from the Worker and also saved with the conversation (`AIConversation`), which is
/// why `id` is encoded: the wire never sends one, so decoding makes a fresh one.
struct AISuggestedItem: Codable, Identifiable {
    var id = UUID()
    let name: String
    let category: PackingRecommendationCategory
    let count: Int
    let kind: Kind
    let accessoryFor: String?
    /// The past trip this was brought on, when the suggestion comes from one
    let fromTrip: String?
    /// The trip list the model picked: a short `AITripList.id` on the wire, replaced with the
    /// list's UUID string before the suggestion is shown or saved. Checked again before use
    var listId: String?

    enum Kind: String, Codable {
        case packing, task
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, category, count, kind, accessoryFor, fromTrip, listId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        // Unknown values fall back rather than failing the whole reply
        let categoryName = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        category = PackingRecommendationCategory(rawValue: categoryName) ?? .other
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 1
        let kindName = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        kind = Kind(rawValue: kindName) ?? .packing
        accessoryFor = try container.decodeIfPresent(String.self, forKey: .accessoryFor)
        fromTrip = try container.decodeIfPresent(String.self, forKey: .fromTrip)
        listId = try container.decodeIfPresent(String.self, forKey: .listId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(category.rawValue, forKey: .category)
        try container.encode(count, forKey: .count)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(accessoryFor, forKey: .accessoryFor)
        try container.encodeIfPresent(fromTrip, forKey: .fromTrip)
        try container.encodeIfPresent(listId, forKey: .listId)
    }
}

// MARK: - Errors

enum AIAssistantError: LocalizedError {
    case notConfigured
    case notSubscribed
    case limitReached(resetsAt: Date?)
    case serverBusy
    case server(Int)
    case network(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "The assistant isn't configured yet."
        case .notSubscribed:
            return "An active subscription is required."
        case .limitReached:
            return "You've used this month's AI messages."
        case .serverBusy:
            return "The assistant is busy right now — try again in a moment."
        case .server:
            return "The assistant ran into a problem. Please try again."
        case .network:
            return "Couldn't reach the assistant. Check your connection."
        case .decoding:
            return "The assistant sent an unexpected response."
        }
    }
}

// MARK: - Service

struct AIAssistantService {
    static let shared = AIAssistantService()

    // Only a 200 is success here; every other status is mapped below.
    private let client = WorkerClient(timeout: 60, successStatuses: 200..<201)

    func sendMessage(_ request: AIAssistantRequest) async throws -> AIAssistantResponse {
        let data: Data
        do {
            data = try await client.post("v1/assistant/message", body: request)
        } catch let error as WorkerClientError {
            throw Self.map(error)
        }
        do {
            return try JSONDecoder().decode(AIAssistantResponse.self, from: data)
        } catch {
            throw AIAssistantError.decoding(error)
        }
    }

    private static func map(_ error: WorkerClientError) -> AIAssistantError {
        switch error {
        case .notConfigured:
            return .notConfigured
        case .encoding(let underlying):
            return .decoding(underlying)
        case .network(let underlying):
            return .network(underlying)
        case .invalidResponse:
            return .server(-1)
        case .status(let code, let data):
            switch code {
            case 401: return .notSubscribed
            case 429: return .limitReached(resetsAt: parseResetsAt(data))
            case 503: return .serverBusy
            default: return .server(code)
            }
        }
    }

    private static func parseResetsAt(_ data: Data) -> Date? {
        struct Body: Decodable { let resetsAt: String? }
        guard let body = try? JSONDecoder().decode(Body.self, from: data),
              let iso = body.resetsAt else { return nil }
        return ISO8601DateFormatter().date(from: iso)
    }
}
