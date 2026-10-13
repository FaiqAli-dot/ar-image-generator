import XCTest
@testable import ARFoodCapture

final class CaptureCoverageMapTests: XCTestCase {
    func testAdaptiveCellsCompletedMissingTargeted() {
        let accepted: Set<Int> = [0, 4] // Front + Front-right required slots
        let snap = CaptureCoverageMapBuilder.snapshot(
            mode: .adaptiveCoverage,
            pass: .horizontal,
            acceptedSlotKeys: accepted,
            targetedSlot: 8
        )
        XCTAssertEqual(snap.cells.count, 8)
        XCTAssertEqual(snap.cells.filter { $0.state == .completed }.count, 2)
        XCTAssertEqual(snap.cells.first { $0.viewpoint.slot == 8 }?.state, .targeted)
        XCTAssertEqual(snap.missingRequiredCount, 6)
    }

    func testRejectDoesNotCountAsCoverage() {
        // Only accepted slot keys are passed in — a rejected shutter never appears.
        let snap = CaptureCoverageMapBuilder.snapshot(
            mode: .adaptiveCoverage,
            pass: .horizontal,
            acceptedSlotKeys: [],
            targetedSlot: 0
        )
        XCTAssertEqual(snap.completedCount, 0)
        XCTAssertEqual(snap.cells.first?.state, .targeted)
    }

    func testCoverageUpdatesAfterDiscard() {
        var keys: Set<Int> = [0, 4, 8, 12, 16, 20, 24, 28]
        XCTAssertTrue(CaptureCoveragePlanner(mode: .adaptiveCoverage).isPassComplete(pass: .horizontal, capturedSlots: keys))
        keys.remove(0)
        let snap = CaptureCoverageMapBuilder.snapshot(
            mode: .adaptiveCoverage,
            pass: .horizontal,
            acceptedSlotKeys: keys,
            targetedSlot: 0
        )
        XCTAssertEqual(snap.cells.first { $0.viewpoint.slot == 0 }?.state, .targeted)
        XCTAssertFalse(CaptureCoveragePlanner(mode: .adaptiveCoverage).isPassComplete(pass: .horizontal, capturedSlots: keys))
    }

    func testIndependentElevationPasses() {
        let keys: Set<Int> = [0, 4, 8, 12, 16, 20, 24, 28] // horizontal only
        let both = CaptureCoverageMapBuilder.bothPasses(
            mode: .adaptiveCoverage,
            acceptedSlotKeys: keys,
            activePass: .elevated,
            targetedSlot: 0
        )
        XCTAssertEqual(both.horizontal.missingRequiredCount, 0)
        XCTAssertEqual(both.elevated.missingRequiredCount, 8)
        XCTAssertEqual(both.elevated.cells.first { $0.state == .targeted }?.viewpoint.slot, 0)
    }

    func testClassicModeUses36Cells() {
        var keys = Set<Int>()
        for i in 0..<36 { keys.insert(i) }
        let snap = CaptureCoverageMapBuilder.snapshot(
            mode: .classic72,
            pass: .horizontal,
            acceptedSlotKeys: keys,
            targetedSlot: nil
        )
        XCTAssertEqual(snap.cells.count, 36)
        XCTAssertEqual(snap.missingRequiredCount, 0)

        keys.remove(10)
        let after = CaptureCoverageMapBuilder.snapshot(
            mode: .classic72,
            pass: .horizontal,
            acceptedSlotKeys: keys,
            targetedSlot: 10
        )
        XCTAssertEqual(after.cells.first { $0.viewpoint.slot == 10 }?.state, .targeted)
        XCTAssertEqual(after.missingRequiredCount, 1)
    }
}

final class CaptureReviewLogicTests: XCTestCase {
    func testOrderedByPassThenAzimuth() {
        let frames = [
            RawCaptureFrame(image: UIImage(), azimuth: 90, elevation: 0, distance: 0.45, capturedAt: Date(), slotKey: 9),
            RawCaptureFrame(image: UIImage(), azimuth: 0, elevation: 15, distance: 0.45, capturedAt: Date(), slotKey: 100),
            RawCaptureFrame(image: UIImage(), azimuth: 0, elevation: 0, distance: 0.45, capturedAt: Date(), slotKey: 0)
        ]
        let items = CaptureReviewLogic.orderedItems(
            mode: .adaptiveCoverage,
            frames: frames,
            slotKeysInOrder: [9, 100, 0]
        )
        XCTAssertEqual(items.map(\.slotKey), [0, 9, 100])
    }

    func testDiscardWarnsWhenRequiredUncovered() {
        let frames = (0..<8).map { i -> RawCaptureFrame in
            RawCaptureFrame(
                image: UIImage(),
                azimuth: Double(i * 45),
                elevation: 0,
                distance: 0.45,
                capturedAt: Date(),
                slotKey: i * 4,
                qualityFlag: i == 0 ? .blurry : nil
            )
        }
        let keys = frames.map(\.slotKey)
        let result = CaptureReviewLogic.afterDiscard(
            mode: .adaptiveCoverage,
            slotKey: 0,
            frames: frames,
            slotKeysInOrder: keys
        )
        XCTAssertNotNil(result.warning)
        XCTAssertFalse(result.canProcess)
        XCTAssertEqual(result.acceptedSlots.count, 7)
        XCTAssertTrue(frames[0].qualityFlag == .blurry)
    }

    func testProcessingBlockedUntilBothPassesComplete() {
        var keys = Set((0..<8).map { $0 * 4 })
        XCTAssertFalse(CaptureReviewLogic.canProcess(mode: .adaptiveCoverage, acceptedSlotKeys: keys))
        for i in 0..<8 { keys.insert(100 + i * 4) }
        XCTAssertTrue(CaptureReviewLogic.canProcess(mode: .adaptiveCoverage, acceptedSlotKeys: keys))
    }

    func testClassicProcessingRequires72() {
        var keys = Set((0..<36).map { $0 })
        XCTAssertFalse(CaptureReviewLogic.canProcess(mode: .classic72, acceptedSlotKeys: keys))
        for i in 0..<36 { keys.insert(100 + i) }
        XCTAssertTrue(CaptureReviewLogic.canProcess(mode: .classic72, acceptedSlotKeys: keys))
    }

    func testSnapshotIncludesReviewFields() throws {
        let snap = CaptureSessionSnapshot(
            mode: .adaptiveCoverage,
            passRaw: 1,
            capturedSlotKeys: [0, 4],
            frameRecords: [
                PersistedCaptureFrame(
                    azimuth: 0,
                    elevation: 0,
                    distance: 0.45,
                    capturedAt: Date(timeIntervalSince1970: 1),
                    slotKey: 0,
                    imageFileName: "recover_000.jpg",
                    qualityFlagRaw: CaptureQualityIssue.blurry.rawValue
                )
            ],
            widthCm: 12,
            objectName: "Dish",
            savedAt: Date(timeIntervalSince1970: 2),
            isPaused: true,
            isInReview: true,
            pendingRetakeSlotKey: 8
        )
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(CaptureSessionSnapshot.self, from: data)
        XCTAssertEqual(decoded.isInReview, true)
        XCTAssertEqual(decoded.pendingRetakeSlotKey, 8)
        XCTAssertEqual(decoded.frameRecords.first?.qualityFlag, .blurry)
    }
}
