import Foundation

#if DEBUG
/// Lightweight networking / deep-link model checks (run via XCTest on macOS, or inspect logic here).
/// Full ARKit UI tests are not required for Phase 2.
enum NetworkingModelFixtures {
    static let sampleUploadResponseJSON = """
    {
      "id": "abcdef0123456789abcdef0123456789",
      "name": "Demo Burger",
      "widthCm": 12,
      "viewCount": 72,
      "arUrl": "https://example.com/ar/abcdef0123456789abcdef0123456789",
      "apiUrl": "https://example.com/api/objects/abcdef0123456789abcdef0123456789",
      "deepLink": "arfood://object/abcdef0123456789abcdef0123456789"
    }
    """

    static let sampleRemoteObjectJSON = """
    {
      "id": "abcdef0123456789abcdef0123456789",
      "name": "Demo Burger",
      "createdAt": "2026-01-01T00:00:00Z",
      "widthCm": 12,
      "viewCount": 2,
      "isDemo": true,
      "schemaVersion": 1,
      "kind": "photographicARObject",
      "views": [
        { "azimuth": 0, "elevation": 0, "image": "view_000.png" },
        { "azimuth": 10, "elevation": 0, "image": "view_001.png" }
      ],
      "arUrl": "https://example.com/ar/abcdef0123456789abcdef0123456789",
      "deepLink": "arfood://object/abcdef0123456789abcdef0123456789",
      "imageBaseUrl": "https://example.com/api/objects/abcdef0123456789abcdef0123456789/images",
      "thumbnailUrl": "https://example.com/api/objects/abcdef0123456789abcdef0123456789/thumbnail"
    }
    """

    static func decodeUploadResponse() throws -> UploadObjectResponse {
        let data = Data(sampleUploadResponseJSON.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(UploadObjectResponse.self, from: data)
    }

    static func decodeRemoteObject() throws -> RemoteObjectDTO {
        let data = Data(sampleRemoteObjectJSON.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RemoteObjectDTO.self, from: data)
    }

    static func assertDeepLinkParsing() -> Bool {
        let id = "abcdef0123456789abcdef0123456789"
        guard let objectURL = URL(string: "arfood://object/\(id)") else { return false }
        guard RemoteObjectService.remoteId(from: objectURL) == id else { return false }
        guard let https = URL(string: "https://api.example.com/ar/\(id)") else { return false }
        guard RemoteObjectService.remoteId(from: https) == id else { return false }
        guard let capture = URL(string: "arfood://capture") else { return false }
        guard RemoteObjectService.isCaptureDeepLink(capture) else { return false }
        guard RemoteObjectService.remoteId(from: URL(string: "arfood://object/../etc")!) == nil else { return false }
        return true
    }
}
#endif
