import XCTest
@testable import ARFoodCapture

final class CaptureQualityRulesTests: XCTestCase {
    func testAcceptsHealthyMetrics() {
        let decision = CaptureQualityRules.decide(
            blurScore: 80,
            meanLuma: 0.45,
            duplicateDistance: 0.4,
            phoneStable: true
        )
        XCTAssertEqual(decision, .accept)
    }

    func testRejectsBlurWhenUnstable() {
        let decision = CaptureQualityRules.decide(
            blurScore: 20,
            meanLuma: 0.45,
            duplicateDistance: 0.4,
            phoneStable: false
        )
        XCTAssertEqual(decision, .reject(.blurry))
        XCTAssertTrue(decision.shouldOfferRetake)
    }

    func testRejectsDarkAndBright() {
        XCTAssertEqual(
            CaptureQualityRules.decide(blurScore: 80, meanLuma: 0.05, duplicateDistance: 0.5, phoneStable: true),
            .reject(.tooDark)
        )
        XCTAssertEqual(
            CaptureQualityRules.decide(blurScore: 80, meanLuma: 0.95, duplicateDistance: 0.5, phoneStable: true),
            .reject(.tooBright)
        )
    }

    func testNearDuplicateWarnAndReject() {
        XCTAssertEqual(
            CaptureQualityRules.decide(blurScore: 80, meanLuma: 0.5, duplicateDistance: 0.02, phoneStable: true),
            .reject(.nearDuplicate)
        )
        XCTAssertEqual(
            CaptureQualityRules.decide(blurScore: 80, meanLuma: 0.5, duplicateDistance: 0.07, phoneStable: true),
            .warn(.nearDuplicate)
        )
    }

    func testFramingFallsBackToInstruction() {
        let text = CaptureQualityEvaluator.framingInstruction()
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(text.lowercased().contains("centered") || text.lowercased().contains("visible"))
    }
}

final class CaptureRetakeAndPauseTests: XCTestCase {
    func testRetakeRemovesSlotAndPreservesOthers() {
        let frames = [
            RawCaptureFrame(image: UIImage(), azimuth: 0, elevation: 0, distance: 0.45, capturedAt: Date()),
            RawCaptureFrame(image: UIImage(), azimuth: 45, elevation: 0, distance: 0.45, capturedAt: Date()),
            RawCaptureFrame(image: UIImage(), azimuth: 90, elevation: 0, distance: 0.45, capturedAt: Date())
        ]
        let keys = [0, 4, 8]
        let result = CaptureRetakeLogic.retake(slotKey: 4, frames: frames, slotKeysInOrder: keys)
        XCTAssertEqual(result.slotKeys, [0, 8])
        XCTAssertEqual(result.frames.count, 2)
        XCTAssertEqual(result.frames[0].azimuth, 0)
        XCTAssertEqual(result.frames[1].azimuth, 90)
        XCTAssertEqual(result.capturedSlots, Set([0, 8]))
    }

    func testPauseSnapshotValidity() {
        XCTAssertTrue(
            CaptureRetakeLogic.pauseSnapshotValid(mode: .adaptiveCoverage, capturedSlots: [0, 1], frameCount: 2)
        )
        XCTAssertFalse(
            CaptureRetakeLogic.pauseSnapshotValid(mode: .classic72, capturedSlots: [0, 1], frameCount: 1)
        )
    }

    func testSnapshotRoundTripCodable() throws {
        let snap = CaptureSessionSnapshot(
            mode: .adaptiveCoverage,
            passRaw: 0,
            capturedSlotKeys: [0, 4, 8],
            frameRecords: [
                PersistedCaptureFrame(
                    azimuth: 0,
                    elevation: 0,
                    distance: 0.45,
                    capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    slotKey: 0,
                    imageFileName: "recover_000.jpg"
                )
            ],
            widthCm: 12,
            objectName: "Test Dish",
            savedAt: Date(timeIntervalSince1970: 1_700_000_100),
            isPaused: true
        )
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(CaptureSessionSnapshot.self, from: data)
        XCTAssertEqual(decoded, snap)
        XCTAssertEqual(decoded.pass, .horizontal)
    }
}

final class CaptureTrackingMessagesTests: XCTestCase {
    func testPermissionAndMotionMessagesAreActionable() {
        XCTAssertTrue(CaptureTrackingMessages.cameraPermissionDenied().lowercased().contains("settings"))
        XCTAssertTrue(CaptureTrackingMessages.phoneMoving().lowercased().contains("dish"))
        XCTAssertTrue(CaptureTrackingMessages.sessionInterrupted().lowercased().contains("resume"))
    }
}

final class PhotographicOutputCompatibilityTests: XCTestCase {
    func testAdaptiveFramesProduceRendererCompatibleViews() {
        let frames: [RawCaptureFrame] = (0..<8).map { i in
            RawCaptureFrame(
                image: UIImage(),
                azimuth: Double(i * 45),
                elevation: 0,
                distance: CaptureConstants.recommendedDistanceMeters,
                capturedAt: Date()
            )
        } + (0..<8).map { i in
            RawCaptureFrame(
                image: UIImage(),
                azimuth: Double(i * 45),
                elevation: 15,
                distance: CaptureConstants.recommendedDistanceMeters,
                capturedAt: Date()
            )
        }

        let views = frames.enumerated().map { idx, frame in
            CapturedView(
                azimuth: frame.azimuth,
                elevation: frame.elevation,
                image: String(format: "view_%03d.png", idx),
                distance: frame.distance,
                capturedAt: frame.capturedAt
            )
        }

        let object = FoodObject(name: "Compat", widthCm: 12, views: views)
        XCTAssertEqual(object.kind, FoodObject.photographicKind)
        XCTAssertEqual(object.schemaVersion, 1)
        XCTAssertEqual(object.views.count, 16)
        XCTAssertEqual(CapturedView.normalizeAzimuth(-10), 350)

        // Nearest-view scoring must tolerate sparse adaptive spacing (45°).
        let selectorMath = nearestIndex(views: object.views, azimuth: 40, elevation: 2)
        XCTAssertEqual(object.views[selectorMath].azimuth, 45)
    }

    private func nearestIndex(views: [CapturedView], azimuth: Double, elevation: Double) -> Int {
        let scored: [(Int, Double)] = views.enumerated().map { idx, view in
            let azDist = min(
                abs(CapturedView.normalizeAzimuth(view.azimuth) - CapturedView.normalizeAzimuth(azimuth)),
                360 - abs(CapturedView.normalizeAzimuth(view.azimuth) - CapturedView.normalizeAzimuth(azimuth))
            )
            let elDist = abs(view.elevation - elevation) * 2.5
            return (idx, azDist + elDist)
        }.sorted { $0.1 < $1.1 }
        return scored[0].0
    }
}
