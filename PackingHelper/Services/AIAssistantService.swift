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

        var listType: ListType { self == .task ? .task : .packing }
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

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        return URLSession(configuration: config)
    }()

    /// Resolves the Worker base URL, preferring a Developer Menu override for
    /// local `wrangler dev` testing.
    private var baseURL: URL? {
        if let override = UserDefaults.standard.string(forKey: "debug_workerURLOverride"),
           !override.isEmpty,
           let url = URL(string: override) {
            return url
        }
        guard let raw = Bundle.main.infoDictionary?["WORKER_URL"] as? String,
              !raw.isEmpty,
              let url = URL(string: raw) else {
            return nil
        }
        return url
    }

    func sendMessage(_ request: AIAssistantRequest) async throws -> AIAssistantResponse {
        guard let baseURL else { throw AIAssistantError.notConfigured }
        let endpoint = baseURL.appendingPathComponent("v1/assistant/message")

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw AIAssistantError.decoding(error)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw AIAssistantError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AIAssistantError.server(-1)
        }

        switch http.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(AIAssistantResponse.self, from: data)
            } catch {
                throw AIAssistantError.decoding(error)
            }
        case 401:
            throw AIAssistantError.notSubscribed
        case 429:
            throw AIAssistantError.limitReached(resetsAt: Self.parseResetsAt(data))
        case 503:
            throw AIAssistantError.serverBusy
        default:
            throw AIAssistantError.server(http.statusCode)
        }
    }

    private static func parseResetsAt(_ data: Data) -> Date? {
        struct Body: Decodable { let resetsAt: String? }
        guard let body = try? JSONDecoder().decode(Body.self, from: data),
              let iso = body.resetsAt else { return nil }
        return ISO8601DateFormatter().date(from: iso)
    }
}
