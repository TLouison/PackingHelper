//
//  UnsplashService.swift
//  PackingHelper
//
//  Unsplash photo search for trip cover photos, proxied through the
//  PackingHelperWorkers Cloudflare Worker (which holds the Unsplash access key,
//  verifies the subscriber for pages past the first, and caches results). Keep these DTOs in sync with
//  the Worker's HTTP contract (PackingHelperWorkers/README.md).
//

import Foundation

// MARK: - DTOs

struct UnsplashPhoto: Decodable, Identifiable, Hashable {
    struct URLs: Decodable, Hashable {
        let raw: String
        let small: String
    }

    struct Photographer: Decodable, Hashable {
        let name: String
        let username: String
        let profileURL: String
    }

    let id: String
    let width: Int
    let height: Int
    let color: String?
    let blurHash: String?
    let urls: URLs
    let htmlLink: String
    let downloadLocation: String
    let photographer: Photographer
}

struct UnsplashSearchResponse: Decodable {
    let page: Int
    let totalPages: Int
    let results: [UnsplashPhoto]
}

private struct UnsplashSearchRequest: Encodable {
    let rcAppUserId: String
    let query: String
    let page: Int
}

private struct UnsplashDownloadRequest: Encodable {
    let rcAppUserId: String
    let downloadLocation: String
}

// MARK: - Errors

enum UnsplashServiceError: LocalizedError {
    case notConfigured
    case notSubscribed
    case rateLimited
    case server(Int)
    case network(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Photo search isn't configured yet."
        case .notSubscribed:
            return "Packing Helper Plus is required to load more photos."
        case .rateLimited:
            return "Too many searches — try again shortly."
        case .server:
            return "Photo search ran into a problem. Please try again."
        case .network:
            return "Couldn't reach photo search. Check your connection."
        case .decoding:
            return "Photo search sent an unexpected response."
        }
    }
}

// MARK: - Service

struct UnsplashService {
    static let shared = UnsplashService()

    /// Appended to every link back to Unsplash, as the API guidelines require.
    static let referralQueryItems = [
        URLQueryItem(name: "utm_source", value: "packing_helper"),
        URLQueryItem(name: "utm_medium", value: "referral"),
    ]

    static func referralURL(_ raw: String) -> URL? {
        guard var components = URLComponents(string: raw) else { return nil }
        components.queryItems = (components.queryItems ?? []) + referralQueryItems
        return components.url
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    func search(query: String, page: Int) async throws -> UnsplashSearchResponse {
        let body = UnsplashSearchRequest(
            rcAppUserId: AITripContextBuilder.rcAppUserId,
            query: query,
            page: page
        )
        let data = try await post("v1/photos/search", body: body)
        do {
            return try JSONDecoder().decode(UnsplashSearchResponse.self, from: data)
        } catch {
            throw UnsplashServiceError.decoding(error)
        }
    }

    /// Tells Unsplash a photo was selected. Required by the API guidelines;
    /// call once when the user saves a trip with a newly picked photo.
    func trackDownload(_ downloadLocation: String) async throws {
        let body = UnsplashDownloadRequest(
            rcAppUserId: AITripContextBuilder.rcAppUserId,
            downloadLocation: downloadLocation
        )
        _ = try await post("v1/photos/download", body: body)
    }

    private func post(_ path: String, body: some Encodable) async throws -> Data {
        guard let baseURL = WorkerConfig.baseURL else { throw UnsplashServiceError.notConfigured }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(path))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            urlRequest.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw UnsplashServiceError.decoding(error)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw UnsplashServiceError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UnsplashServiceError.server(-1)
        }

        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            throw UnsplashServiceError.notSubscribed
        case 429:
            throw UnsplashServiceError.rateLimited
        default:
            throw UnsplashServiceError.server(http.statusCode)
        }
    }
}
