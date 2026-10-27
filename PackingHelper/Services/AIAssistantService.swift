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
    let tripContext: AITripContext
    let messages: [AIChatMessageDTO]
}

struct AITripContext: Encodable {
    let destinationName: String
    let startDate: String   // yyyy-MM-dd
    let endDate: String     // yyyy-MM-dd
    let durationDays: Int
    let tripType: String
    let accommodation: String
    let packerCount: Int
    let existingItems: [String]
    let weather: AIWeatherContext?  // nil → omitted (synthesized encoder uses encodeIfPresent)
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

struct AISuggestedItem: Decodable, Identifiable {
    let id = UUID()  // client-side identity for ForEach; not from the wire
    let name: String
    let category: PackingRecommendationCategory
    let count: Int
    let kind: Kind
    let accessoryFor: String?

    enum Kind: String, Decodable {
        case packing, task
    }

    private enum CodingKeys: String, CodingKey {
        case name, category, count, kind, accessoryFor
    }
}

// Raw values already match the wire strings ("Clothing", "Electronics", …).
extension PackingRecommendationCategory: Decodable {}

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
