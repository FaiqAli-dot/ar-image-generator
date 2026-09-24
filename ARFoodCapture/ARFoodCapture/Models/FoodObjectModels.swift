import Foundation
import UIKit

/// Photographic multi-view AR object — NOT a mesh / photogrammetry model.
struct FoodObject: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var createdAt: Date
    var widthCm: Double
    var viewCount: Int
    var isDemo: Bool
    var schemaVersion: Int
    var kind: String
    var notes: String?
    var views: [CapturedView]

    // Phase 2 remote pipeline (optional; defaults preserve MVP local objects)
    var syncState: ObjectSyncState
    var remoteId: String?
    var arUrl: String?
    var deepLink: String?
    var lastUploadError: String?
    var objectDescription: String?

    /// Relative folder name under Application Support / bundle DemoBurger
    var storageDirectoryName: String { id }

    static let photographicKind = "photographicARObject"

    init(
        id: String = UUID().uuidString,
        name: String,
        createdAt: Date = Date(),
        widthCm: Double,
        views: [CapturedView],
        isDemo: Bool = false,
        notes: String? = nil,
        syncState: ObjectSyncState = .local,
        remoteId: String? = nil,
        arUrl: String? = nil,
        deepLink: String? = nil,
        lastUploadError: String? = nil,
        objectDescription: String? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.widthCm = widthCm
        self.viewCount = views.count
        self.isDemo = isDemo
        self.schemaVersion = 1
        self.kind = Self.photographicKind
        self.notes = notes
        self.views = views
        self.syncState = syncState
        self.remoteId = remoteId
        self.arUrl = arUrl
        self.deepLink = deepLink
        self.lastUploadError = lastUploadError
        self.objectDescription = objectDescription
    }

    enum CodingKeys: String, CodingKey {
        case id, name, createdAt, widthCm, viewCount, isDemo, schemaVersion, kind, notes, views
        case syncState, remoteId, arUrl, deepLink, lastUploadError, objectDescription
        case description
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        widthCm = try c.decode(Double.self, forKey: .widthCm)
        views = try c.decode([CapturedView].self, forKey: .views)
        viewCount = try c.decodeIfPresent(Int.self, forKey: .viewCount) ?? views.count
        isDemo = try c.decodeIfPresent(Bool.self, forKey: .isDemo) ?? false
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? Self.photographicKind
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        syncState = try c.decodeIfPresent(ObjectSyncState.self, forKey: .syncState) ?? .local
        remoteId = try c.decodeIfPresent(String.self, forKey: .remoteId)
        arUrl = try c.decodeIfPresent(String.self, forKey: .arUrl)
        deepLink = try c.decodeIfPresent(String.self, forKey: .deepLink)
        lastUploadError = try c.decodeIfPresent(String.self, forKey: .lastUploadError)
        objectDescription = try c.decodeIfPresent(String.self, forKey: .objectDescription)
            ?? c.decodeIfPresent(String.self, forKey: .description)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(widthCm, forKey: .widthCm)
        try c.encode(viewCount, forKey: .viewCount)
        try c.encode(isDemo, forKey: .isDemo)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encode(views, forKey: .views)
        try c.encode(syncState, forKey: .syncState)
        try c.encodeIfPresent(remoteId, forKey: .remoteId)
        try c.encodeIfPresent(arUrl, forKey: .arUrl)
        try c.encodeIfPresent(deepLink, forKey: .deepLink)
        try c.encodeIfPresent(lastUploadError, forKey: .lastUploadError)
        try c.encodeIfPresent(objectDescription, forKey: .objectDescription)
    }

    var isRemoteAvailable: Bool {
        remoteId != nil || (arUrl?.isEmpty == false)
    }
}

struct CapturedView: Codable, Identifiable, Hashable {
    var id: String
    var azimuth: Double
    var elevation: Double
    var image: String
    var distance: Double?
    var capturedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, azimuth, elevation, image, distance, capturedAt
    }

    init(
        id: String = UUID().uuidString,
        azimuth: Double,
        elevation: Double,
        image: String,
        distance: Double? = nil,
        capturedAt: Date? = nil
    ) {
        self.id = id
        self.azimuth = Self.normalizeAzimuth(azimuth)
        self.elevation = elevation
        self.image = image
        self.distance = distance
        self.capturedAt = capturedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        azimuth = Self.normalizeAzimuth(try c.decode(Double.self, forKey: .azimuth))
        elevation = try c.decode(Double.self, forKey: .elevation)
        image = try c.decode(String.self, forKey: .image)
        distance = try c.decodeIfPresent(Double.self, forKey: .distance)
        capturedAt = try c.decodeIfPresent(Date.self, forKey: .capturedAt)
    }

    static func normalizeAzimuth(_ value: Double) -> Double {
        var a = value.truncatingRemainder(dividingBy: 360)
        if a < 0 { a += 360 }
        return a
    }
}

enum CapturePass: Int, CaseIterable {
    case horizontal = 0
    case elevated = 1

    var title: String {
        switch self {
        case .horizontal: return "PASS 1 OF 2"
        case .elevated: return "PASS 2 OF 2"
        }
    }

    var instruction: String {
        switch self {
        case .horizontal:
            return "Freeze the phone at food height. Rotate the dish on a turntable. Tap CAPTURE NEXT each ~10°. Do not spin the phone."
        case .elevated:
            return "Raise the phone ~15 cm and tilt down slightly once (~15°) — not a flip. Freeze, then rotate the dish again with CAPTURE NEXT."
        }
    }

    /// Short lines for pass intro overlays.
    var introBullets: [String] {
        switch self {
        case .horizontal:
            return [
                "Freeze phone at table / food height — do not walk or spin it",
                "Rotate only the DISH on the turntable",
                "Tap CAPTURE NEXT after each ~10° dish turn (primary control)"
            ]
        case .elevated:
            return [
                "Raise ~15 cm + slight look-down once — never a 180° phone flip",
                "Freeze the phone again; rotate only the dish",
                "CAPTURE NEXT each step until the ring fills"
            ]
        }
    }

    var targetElevationDegrees: Double {
        switch self {
        case .horizontal: return 0
        case .elevated: return 15
        }
    }

    var stepCount: Int { 36 }
}

enum CaptureConstants {
    static let azimuthStepDegrees: Double = 10
    static let viewsPerPass: Int = 36
    static let totalViews: Int = 72
    static let recommendedDistanceMeters: Double = 0.45
    static let distanceToleranceMeters: Double = 0.18
    static let azimuthCaptureTolerance: Double = 4.5
    /// Practical CoreMotion energy threshold for “phone stable enough to shoot.”
    static let phoneStableMotionThreshold: Double = 1.35
}

struct QualityWarning: Identifiable, Equatable {
    let id: UUID
    let message: String

    init(message: String) {
        self.id = UUID()
        self.message = message
    }
}

/// Phase extension notes (capture → upload → AR unchanged; Phase 3 changes azimuth semantics).
enum FutureArchitecture {
    static let note = """
    Phase 3: phone stays roughly fixed; object rotates on a turntable. Captured azimuth = object orientation (ManualRotationProvider ± Vision assist), never phone yaw. MotorizedRotationProvider is a stub only. Phase 2 remote pipeline unchanged: photographic AR Object → upload → permanent arUrl → QR → native iOS remote viewer (arfood://).
    """
}
