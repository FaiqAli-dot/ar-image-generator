import Foundation

/// Sync / availability state for MY OBJECTS (Phase 2).
enum ObjectSyncState: String, Codable, Hashable, CaseIterable {
    case local
    case uploading
    case remote
    case ready
    case failed

    var badgeTitle: String {
        rawValue.uppercased()
    }
}
