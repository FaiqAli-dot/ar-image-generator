import Foundation

enum APIClientError: LocalizedError, Equatable {
    case notConfigured
    case invalidURL
    case httpStatus(Int, String?)
    case decoding
    case cancelled
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "API base URL is not configured. Set ARFoodAPIBaseURL in Info.plist or Debug settings."
        case .invalidURL:
            return "Invalid API URL"
        case .httpStatus(let code, let body):
            if let body, !body.isEmpty { return "Server error (\(code)): \(body)" }
            return "Server error (\(code))"
        case .decoding:
            return "Could not decode server response"
        case .cancelled:
            return "Cancelled"
        case .transport(let message):
            return message
        }
    }
}

/// Shared async HTTP helper for Phase 2 networking.
actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func getJSON<T: Decodable>(_ path: String, type: T.Type) async throws -> T {
        guard let url = APIConfig.url(path: path) else { throw APIClientError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60
        let (data, response) = try await data(for: request)
        try validate(response: response, data: data)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIClientError.decoding
        }
    }

    func getData(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 120
        let (data, response) = try await data(for: request)
        try validate(response: response, data: data)
        return data
    }

    func uploadMultipart(
        path: String,
        multipart: MultipartFormData,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Data {
        guard let url = APIConfig.url(path: path) else { throw APIClientError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(multipart.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 600
        request.httpBody = multipart.body
        progress?(0.05)
        let (data, response) = try await data(for: request)
        progress?(1.0)
        try validate(response: response, data: data)
        return data
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch is CancellationError {
            throw APIClientError.cancelled
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw APIClientError.cancelled
        } catch {
            throw APIClientError.transport(error.localizedDescription)
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw APIClientError.httpStatus(http.statusCode, body)
        }
    }

    nonisolated var jsonDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

struct MultipartFormData: Sendable {
    let boundary: String
    let body: Data

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    init(boundary: String = "arfood-\(UUID().uuidString)", parts: [Part]) {
        self.boundary = boundary
        var data = Data()
        for part in parts {
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            if let filename = part.filename {
                data.append(
                    "Content-Disposition: form-data; name=\"\(part.name)\"; filename=\"\(filename)\"\r\n"
                        .data(using: .utf8)!
                )
                data.append("Content-Type: \(part.mimeType)\r\n\r\n".data(using: .utf8)!)
            } else {
                data.append(
                    "Content-Disposition: form-data; name=\"\(part.name)\"\r\n\r\n".data(using: .utf8)!
                )
            }
            data.append(part.data)
            data.append("\r\n".data(using: .utf8)!)
        }
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        self.body = data
    }

    struct Part: Sendable {
        let name: String
        let data: Data
        let filename: String?
        let mimeType: String

        static func field(_ name: String, _ value: String) -> Part {
            Part(name: name, data: Data(value.utf8), filename: nil, mimeType: "text/plain")
        }

        static func file(_ name: String, filename: String, mimeType: String, data: Data) -> Part {
            Part(name: name, data: data, filename: filename, mimeType: mimeType)
        }
    }
}
