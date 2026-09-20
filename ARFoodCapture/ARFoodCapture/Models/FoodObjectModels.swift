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
        notes: String? = nil
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
        case .horizontal: return "Capture from around the sides."
        case .elevated: return "Raise the phone slightly. Capture from above."
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
}

struct QualityWarning: Identifiable, Equatable {
    let id: UUID
    let message: String

    init(message: String) {
        self.id = UUID()
        self.message = message
    }
}

/// Future architecture hook (not built in MVP): Restaurant → Dish → AR Object → QR.
enum FutureArchitecture {
    static let note = "Reserved for Restaurant → Dish → photographic AR Object → QR → Customer Web Viewer."
}
