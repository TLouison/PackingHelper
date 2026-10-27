//
//  WorkerClient.swift
//  PackingHelper
//
//  Shared transport for the PackingHelperWorkers Cloudflare Worker: base URL
//  (with the DEBUG override), JSON POST request building, and the split between
//  transport failures and HTTP status codes. Each service maps the result onto
//  its own error type, since the services word and group statuses differently.
//  The subscriber is identified by the rcAppUserId in each request body, which
//  the Worker verifies against RevenueCat, so there are no auth headers.
//

import Foundation

/// PackingHelperWorkers location, shared by every Worker-backed service.
enum WorkerConfig {
    /// Resolves the Worker base URL. Debug builds prefer a `debug_workerURLOverride`
    /// for local `wrangler dev` testing; release builds always use the bundled URL.
    static var baseURL: URL? {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "debug_workerURLOverride"),
           !override.isEmpty,
           let url = URL(string: override) {
            return url
        }
        #endif
        guard let raw = Bundle.main.infoDictionary?["WORKER_URL"] as? String,
              !raw.isEmpty,
              let url = URL(string: raw) else {
            return nil
        }
        return url
    }
}

/// What can go wrong talking to the Worker, before a service gives it a name.
enum WorkerClientError: Error {
    case notConfigured
    case encoding(Error)
    case network(Error)
    /// The response was not HTTP.
    case invalidResponse
    /// A status outside the accepted range, with the body for services that read it.
    case status(Int, Data)
}

struct WorkerClient {
    private let session: URLSession
    private let successStatuses: Range<Int>

    /// - Parameters:
    ///   - timeout: per-request timeout in seconds.
    ///   - successStatuses: statuses returned as data; anything else throws `.status`.
    init(timeout: TimeInterval, successStatuses: Range<Int> = 200..<300) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        self.session = URLSession(configuration: config)
        self.successStatuses = successStatuses
    }

    /// POSTs `body` as JSON to `path` under the Worker base URL and returns the response body.
    func post(_ path: String, body: some Encodable) async throws -> Data {
        guard let baseURL = WorkerConfig.baseURL else { throw WorkerClientError.notConfigured }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(path))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            urlRequest.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw WorkerClientError.encoding(error)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw WorkerClientError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw WorkerClientError.invalidResponse
        }
        guard successStatuses.contains(http.statusCode) else {
            throw WorkerClientError.status(http.statusCode, data)
        }
        return data
    }
}
