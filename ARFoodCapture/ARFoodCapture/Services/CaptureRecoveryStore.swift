import Foundation
import UIKit

/// Serializable pause/resume snapshot for an in-progress guided capture.
struct CaptureSessionSnapshot: Codable, Equatable {
    var mode: CaptureSequenceMode
    var passRaw: Int
    var capturedSlotKeys: [Int]
    var frameRecords: [PersistedCaptureFrame]
    var widthCm: Double
    var objectName: String
    var savedAt: Date
    var isPaused: Bool

    var pass: CapturePass {
        CapturePass(rawValue: passRaw) ?? .horizontal
    }
}

struct PersistedCaptureFrame: Codable, Equatable {
    var azimuth: Double
    var elevation: Double
    var distance: Double?
    var capturedAt: Date
    var slotKey: Int
    /// Relative filename under the recovery images directory.
    var imageFileName: String
}

/// Disk-backed pause/resume + retake integrity helpers.
@MainActor
final class CaptureRecoveryStore {
    static let shared = CaptureRecoveryStore()

    private let fileManager = FileManager.default
    private let snapshotFileName = "capture_session_snapshot.json"

    private var rootURL: URL {
        let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ARFoodCapture/CaptureRecovery", isDirectory: true)
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private var snapshotURL: URL { rootURL.appendingPathComponent(snapshotFileName) }
    private var imagesURL: URL {
        let url = rootURL.appendingPathComponent("images", isDirectory: true)
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    var hasSavedSession: Bool { fileManager.fileExists(atPath: snapshotURL.path) }

    func save(
        mode: CaptureSequenceMode,
        pass: CapturePass,
        capturedSlots: Set<Int>,
        frames: [RawCaptureFrame],
        slotKeysInOrder: [Int],
        widthCm: Double,
        objectName: String,
        isPaused: Bool
    ) throws {
        try clearImagesOnly()
        var records: [PersistedCaptureFrame] = []
        for (idx, frame) in frames.enumerated() {
            let slotKey = idx < slotKeysInOrder.count ? slotKeysInOrder[idx] : idx
            let name = String(format: "recover_%03d.jpg", idx)
            if let data = frame.image.jpegData(compressionQuality: 0.85) {
                try data.write(to: imagesURL.appendingPathComponent(name), options: .atomic)
            }
            records.append(
                PersistedCaptureFrame(
                    azimuth: frame.azimuth,
                    elevation: frame.elevation,
                    distance: frame.distance,
                    capturedAt: frame.capturedAt,
                    slotKey: slotKey,
                    imageFileName: name
                )
            )
        }
        let snap = CaptureSessionSnapshot(
            mode: mode,
            passRaw: pass.rawValue,
            capturedSlotKeys: Array(capturedSlots).sorted(),
            frameRecords: records,
            widthCm: widthCm,
            objectName: objectName,
            savedAt: Date(),
            isPaused: isPaused
        )
        let data = try JSONEncoder().encode(snap)
        try data.write(to: snapshotURL, options: .atomic)
    }

    func loadSnapshot() throws -> CaptureSessionSnapshot? {
        guard fileManager.fileExists(atPath: snapshotURL.path) else { return nil }
        let data = try Data(contentsOf: snapshotURL)
        return try JSONDecoder().decode(CaptureSessionSnapshot.self, from: data)
    }

    func loadFrames(from snapshot: CaptureSessionSnapshot) -> [RawCaptureFrame] {
        snapshot.frameRecords.compactMap { rec in
            let url = imagesURL.appendingPathComponent(rec.imageFileName)
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
            return RawCaptureFrame(
                image: image,
                azimuth: rec.azimuth,
                elevation: rec.elevation,
                distance: rec.distance,
                capturedAt: rec.capturedAt
            )
        }
    }

    func clear() throws {
        if fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.removeItem(at: rootURL)
        }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    private func clearImagesOnly() throws {
        if fileManager.fileExists(atPath: imagesURL.path) {
            try fileManager.removeItem(at: imagesURL)
        }
        try fileManager.createDirectory(at: imagesURL, withIntermediateDirectories: true)
    }
}

/// In-memory retake / slot integrity helpers (unit-testable without disk).
enum CaptureRetakeLogic {
    /// Removes a slot and its frame; returns updated frames + keys preserving order.
    static func retake(
        slotKey: Int,
        frames: [RawCaptureFrame],
        slotKeysInOrder: [Int]
    ) -> (frames: [RawCaptureFrame], slotKeys: [Int], capturedSlots: Set<Int>) {
        var newFrames: [RawCaptureFrame] = []
        var newKeys: [Int] = []
        for (idx, key) in slotKeysInOrder.enumerated() {
            guard key != slotKey else { continue }
            if frames.indices.contains(idx) {
                newFrames.append(frames[idx])
                newKeys.append(key)
            }
        }
        return (newFrames, newKeys, Set(newKeys))
    }

    static func pauseSnapshotValid(
        mode: CaptureSequenceMode,
        capturedSlots: Set<Int>,
        frameCount: Int
    ) -> Bool {
        frameCount == capturedSlots.count && frameCount >= 0
            && (mode == .classic72 || mode == .adaptiveCoverage)
    }
}
