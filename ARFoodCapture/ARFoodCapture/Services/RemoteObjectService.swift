import Foundation
import UIKit

/// Fetch remote photographic objects and cache them locally for the existing AR renderer.
final class RemoteObjectService {
    static let shared = RemoteObjectService()

    private let client = APIClient.shared

    @MainActor
    func fetchMetadata(remoteId: String) async throws -> RemoteObjectDTO {
        try await client.getJSON("/api/objects/\(remoteId)", type: RemoteObjectDTO.self)
    }

    /// Downloads metadata + transparent views into the local library (syncState = ready).
    @MainActor
    @discardableResult
    func downloadAndInstall(remoteId: String, store: ObjectLibraryStore) async throws -> FoodObject {
        let dto = try await fetchMetadata(remoteId: remoteId)
        guard let imageBase = dto.imageBaseUrl.flatMap(URL.init(string:)) else {
            throw APIClientError.transport("Missing imageBaseUrl")
        }

        var images: [String: Data] = [:]
        for view in dto.views {
            let url = imageBase.appendingPathComponent(view.image)
            let data = try await client.getData(url)
            images[view.image] = data
        }

        var thumb: Data?
        if let thumbURL = dto.thumbnailUrl.flatMap(URL.init(string:)) {
            thumb = try? await client.getData(thumbURL)
        }

        let localId = "remote-\(dto.id)"
        let object = FoodObject(
            id: localId,
            name: dto.name,
            createdAt: dto.createdAt ?? Date(),
            widthCm: dto.widthCm,
            views: dto.views,
            isDemo: dto.isDemo ?? false,
            notes: dto.notes ?? dto.description,
            syncState: .ready,
            remoteId: dto.id,
            arUrl: dto.arUrl,
            deepLink: dto.deepLink,
            lastUploadError: nil,
            objectDescription: dto.description
        )
        try store.save(object, images: images, thumbnail: thumb)
        return object
    }

    /// Resolve an incoming deep link / universal URL to a remote object id.
    static func remoteId(from url: URL) -> String? {
        if url.scheme == "arfood" {
            let host = url.host?.lowercased()
            if host == "object" {
                let id = url.pathComponents.filter { $0 != "/" }.first
                return sanitize(id)
            }
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count >= 2, parts[0].lowercased() == "object" {
                return sanitize(parts[1])
            }
            if parts.count == 1, parts[0].count >= 8 {
                return sanitize(parts[0])
            }
            return nil
        }

        let parts = url.pathComponents.filter { $0 != "/" }
        if parts.count >= 2, parts[0] == "ar" || (parts[0] == "api" && parts.count >= 3 && parts[1] == "objects") {
            let id = parts[0] == "ar" ? parts[1] : parts[2]
            return sanitize(id)
        }
        return nil
    }

    static func isCaptureDeepLink(_ url: URL) -> Bool {
        if url.scheme == "arfood" {
            if url.host?.lowercased() == "capture" { return true }
            let parts = url.pathComponents.filter { $0 != "/" }
            return parts.first?.lowercased() == "capture"
        }
        return url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased() == "capture"
    }

    private static func sanitize(_ id: String?) -> String? {
        guard let id, !id.isEmpty else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard id.unicodeScalars.allSatisfy({ allowed.contains($0) }), id.count >= 8, id.count <= 64 else {
            return nil
        }
        return id
    }
}
