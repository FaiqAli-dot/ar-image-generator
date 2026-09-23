import Foundation

struct RemoteObjectDTO: Codable, Equatable {
    let id: String
    let name: String
    let createdAt: Date?
    let widthCm: Double
    let viewCount: Int?
    let isDemo: Bool?
    let schemaVersion: Int?
    let kind: String?
    let notes: String?
    let description: String?
    let views: [CapturedView]
    let arUrl: String?
    let apiUrl: String?
    let deepLink: String?
    let imageBaseUrl: String?
    let thumbnailUrl: String?
}

struct UploadObjectResponse: Codable, Equatable {
    let id: String
    let name: String
    let widthCm: Double
    let viewCount: Int
    let createdAt: String?
    let description: String?
    let isDemo: Bool?
    let kind: String?
    let arUrl: String
    let apiUrl: String?
    let deepLink: String?
}

/// Upload local photographic views + metadata to the Phase 2 object API.
@MainActor
final class ObjectUploadService: ObservableObject {
    static let shared = ObjectUploadService()

    @Published private(set) var progress: Double = 0
    @Published private(set) var stage: String = ""
    private var currentTask: Task<UploadObjectResponse, Error>?

    private let client = APIClient.shared

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        stage = "Cancelled"
    }

    func upload(
        object: FoodObject,
        store: ObjectLibraryStore,
        name: String,
        widthCm: Double,
        description: String?
    ) async throws -> UploadObjectResponse {
        guard APIConfig.isConfigured else { throw APIClientError.notConfigured }

        progress = 0
        stage = "Preparing…"

        var viewsPayload: [[String: Any]] = []
        var parts: [MultipartFormData.Part] = []
        let total = max(object.views.count, 1)

        for (index, view) in object.views.enumerated() {
            guard let data = try? Data(contentsOf: store.imageURL(for: object, view: view)) else {
                throw APIClientError.transport("Missing local image \(view.image)")
            }
            parts.append(.file("images", filename: view.image, mimeType: "image/png", data: data))
            var entry: [String: Any] = [
                "id": view.id,
                "azimuth": view.azimuth,
                "elevation": view.elevation,
                "image": view.image
            ]
            if let distance = view.distance { entry["distance"] = distance }
            viewsPayload.append(entry)
            progress = Double(index + 1) / Double(total) * 0.45
            stage = "Packing views \(index + 1)/\(total)"
        }

        if let thumb = try? Data(contentsOf: store.thumbnailURL(for: object.id)), !thumb.isEmpty {
            parts.append(.file("thumbnail", filename: "thumb.png", mimeType: "image/png", data: thumb))
        }

        var meta: [String: Any] = [
            "name": name,
            "widthCm": widthCm,
            "views": viewsPayload,
            "isDemo": object.isDemo
        ]
        if let description, !description.isEmpty {
            meta["description"] = description
        }
        let metaData = try JSONSerialization.data(withJSONObject: meta, options: [])
        guard let metaString = String(data: metaData, encoding: .utf8) else {
            throw APIClientError.decoding
        }
        parts.insert(.field("metadata", metaString), at: 0)

        let multipart = MultipartFormData(parts: parts)
        stage = "Uploading…"
        progress = 0.5

        let task = Task {
            try await client.uploadMultipart(path: "/api/objects", multipart: multipart) { [weak self] value in
                Task { @MainActor in
                    self?.progress = 0.5 + value * 0.5
                }
            }
        }
        currentTask = task

        do {
            let data = try await task.value
            let decoded = try client.jsonDecoder.decode(UploadObjectResponse.self, from: data)
            progress = 1
            stage = "Done"
            currentTask = nil
            return decoded
        } catch is CancellationError {
            currentTask = nil
            throw APIClientError.cancelled
        } catch {
            currentTask = nil
            throw error
        }
    }
}
