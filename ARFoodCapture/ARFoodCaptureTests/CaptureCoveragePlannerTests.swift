import XCTest
@testable import ARFoodCapture

final class CaptureCoveragePlannerTests: XCTestCase {
    func testClassicHas72RequiredViewpoints() {
        let planner = CaptureCoveragePlanner(mode: .classic72)
        XCTAssertEqual(planner.viewpoints(for: .horizontal).count, 36)
        XCTAssertEqual(planner.viewpoints(for: .elevated).count, 36)
        XCTAssertEqual(planner.expectedMinimumTotal, 72)
        XCTAssertTrue(planner.viewpoints(for: .horizontal).allSatisfy(\.isRequired))
    }

    func testAdaptiveRequiredSectorsCompletable() {
        let planner = CaptureCoveragePlanner(mode: .adaptiveCoverage)
        let required = planner.requiredViewpoints(for: .horizontal)
        XCTAssertEqual(required.count, 8)
        XCTAssertEqual(planner.expectedMinimumTotal, 16)

        var captured = Set<Int>()
        for vp in required {
            XCTAssertFalse(planner.isPassComplete(pass: .horizontal, capturedSlots: captured))
            captured.insert(vp.globalSlotKey)
        }
        XCTAssertTrue(planner.isPassComplete(pass: .horizontal, capturedSlots: captured))
        XCTAssertFalse(planner.isSessionComplete(capturedSlots: captured))

        for vp in planner.requiredViewpoints(for: .elevated) {
            captured.insert(vp.globalSlotKey)
        }
        XCTAssertTrue(planner.isSessionComplete(capturedSlots: captured))
    }

    func testNextViewpointPrefersRequiredBeforeFills() {
        let planner = CaptureCoveragePlanner(mode: .adaptiveCoverage)
        let first = planner.nextViewpoint(pass: .horizontal, capturedSlots: [])
        XCTAssertEqual(first?.slot, 0)
        XCTAssertEqual(first?.isRequired, true)

        var captured: Set<Int> = [0, 4, 8, 12, 16, 20, 24, 28]
        XCTAssertTrue(planner.isPassComplete(pass: .horizontal, capturedSlots: captured))
        let fill = planner.nextViewpoint(pass: .horizontal, capturedSlots: captured)
        XCTAssertEqual(fill?.isRequired, false)
    }

    func testViewpointAssociationAndLabels() {
        let planner = CaptureCoveragePlanner(mode: .adaptiveCoverage)
        let vp = planner.associate(azimuthDegrees: 90, pass: .horizontal)
        XCTAssertEqual(vp?.slot, 9)
        XCTAssertTrue(ViewpointGuidance.compassName(azimuth: 0).contains("Front"))
        XCTAssertEqual(ViewpointGuidance.compassName(azimuth: 90), "Right")
        XCTAssertEqual(ViewpointGuidance.compassName(azimuth: 180), "Back")
        XCTAssertEqual(ViewpointGuidance.compassName(azimuth: 270), "Left")
    }

    func testMissingSectorsReported() {
        let planner = CaptureCoveragePlanner(mode: .adaptiveCoverage)
        let missing = planner.missingSectorIndices(pass: .horizontal, capturedSlots: [0, 4])
        XCTAssertEqual(missing.count, 6)
        XCTAssertFalse(missing.contains(0))
        XCTAssertFalse(missing.contains(1))
    }

    func testFillRequestedOnlyWhenQualityWeak() {
        let planner = CaptureCoveragePlanner(mode: .adaptiveCoverage)
        let fill = planner.shouldRequestFill(
            afterRequiredSlot: 0,
            pass: .horizontal,
            capturedSlots: [0],
            lastQualityAccepted: false
        )
        XCTAssertEqual(fill?.slot, 2)
        let none = planner.shouldRequestFill(
            afterRequiredSlot: 0,
            pass: .horizontal,
            capturedSlots: [0],
            lastQualityAccepted: true
        )
        XCTAssertNil(none)
    }
}
