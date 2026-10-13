import Foundation

/// Capture density mode. Classic keeps the proven ~72 / 10° sequence; adaptive
/// prefers fewer sector-complete shots and only adds extras when coverage/quality needs them.
enum CaptureSequenceMode: String, Codable, CaseIterable, Identifiable {
    case classic72
    case adaptiveCoverage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic72: return "Classic 72"
        case .adaptiveCoverage: return "Adaptive coverage"
        }
    }

    var subtitle: String {
        switch self {
        case .classic72:
            return "Full 36 angles × 2 heights (~72 photos). Best for A/B comparison."
        case .adaptiveCoverage:
            return "8 sectors × 2 heights first; adds fills only for gaps or weak shots."
        }
    }
}

/// One capture target associated with an azimuth slot and elevation pass.
struct CaptureViewpoint: Equatable, Hashable, Identifiable {
    /// Slot index within a pass (0…35 classic, or adaptive subset).
    let slot: Int
    let pass: CapturePass
    /// Whether this viewpoint is required before the pass/session can complete.
    let isRequired: Bool
    /// Human label for next-photo coaching.
    let label: String

    var id: String { "\(pass.rawValue)-\(slot)" }

    var azimuthDegrees: Double {
        Double(slot) * CaptureConstants.azimuthStepDegrees
    }

    var globalSlotKey: Int {
        slot + pass.rawValue * 100
    }
}

/// Sector-based coverage planner. Pure logic — no camera / ARKit dependency.
struct CaptureCoveragePlanner: Equatable {
    let mode: CaptureSequenceMode

    /// Adaptive required sectors every 45° (8 per pass). Classic uses every 10° slot.
    static let adaptiveSectorStepSlots = 4 // 4 × 10° = 45°
    static let adaptiveFillStepSlots = 2   // optional mid-sector fills at 20°

    init(mode: CaptureSequenceMode = .adaptiveCoverage) {
        self.mode = mode
    }

    /// Ordered viewpoints for a pass (required first in adaptive; full sequence in classic).
    func viewpoints(for pass: CapturePass) -> [CaptureViewpoint] {
        switch mode {
        case .classic72:
            return (0..<CaptureConstants.viewsPerPass).map { slot in
                CaptureViewpoint(
                    slot: slot,
                    pass: pass,
                    isRequired: true,
                    label: ViewpointGuidance.label(forSlot: slot, pass: pass)
                )
            }
        case .adaptiveCoverage:
            var list: [CaptureViewpoint] = []
            for slot in stride(from: 0, to: CaptureConstants.viewsPerPass, by: Self.adaptiveSectorStepSlots) {
                list.append(
                    CaptureViewpoint(
                        slot: slot,
                        pass: pass,
                        isRequired: true,
                        label: ViewpointGuidance.label(forSlot: slot, pass: pass)
                    )
                )
            }
            // Optional fills between required sectors (not required for completion).
            for slot in stride(from: Self.adaptiveFillStepSlots, to: CaptureConstants.viewsPerPass, by: Self.adaptiveSectorStepSlots) {
                list.append(
                    CaptureViewpoint(
                        slot: slot,
                        pass: pass,
                        isRequired: false,
                        label: ViewpointGuidance.label(forSlot: slot, pass: pass)
                    )
                )
            }
            return list.sorted { $0.slot < $1.slot }
        }
    }

    func requiredViewpoints(for pass: CapturePass) -> [CaptureViewpoint] {
        viewpoints(for: pass).filter(\.isRequired)
    }

    var expectedMinimumTotal: Int {
        switch mode {
        case .classic72:
            return CaptureConstants.totalViews
        case .adaptiveCoverage:
            return requiredViewpoints(for: .horizontal).count
                + requiredViewpoints(for: .elevated).count
        }
    }

    var expectedMaximumTotal: Int {
        switch mode {
        case .classic72:
            return CaptureConstants.totalViews
        case .adaptiveCoverage:
            return viewpoints(for: .horizontal).count + viewpoints(for: .elevated).count
        }
    }

    /// Next uncaptured viewpoint in planning order (required before optional fills).
    func nextViewpoint(pass: CapturePass, capturedSlots: Set<Int>) -> CaptureViewpoint? {
        let capturedInPass = Set(capturedSlots.compactMap { key -> Int? in
            let v = key - pass.rawValue * 100
            return (0..<CaptureConstants.viewsPerPass).contains(v) ? v : nil
        })
        let ordered = viewpoints(for: pass).sorted { lhs, rhs in
            if lhs.isRequired != rhs.isRequired { return lhs.isRequired && !rhs.isRequired }
            return lhs.slot < rhs.slot
        }
        return ordered.first { !capturedInPass.contains($0.slot) }
    }

    func isPassComplete(pass: CapturePass, capturedSlots: Set<Int>) -> Bool {
        let capturedInPass = Set(capturedSlots.compactMap { key -> Int? in
            let v = key - pass.rawValue * 100
            return (0..<CaptureConstants.viewsPerPass).contains(v) ? v : nil
        })
        switch mode {
        case .classic72:
            return capturedInPass.count >= CaptureConstants.viewsPerPass
        case .adaptiveCoverage:
            let required = Set(requiredViewpoints(for: pass).map(\.slot))
            return required.isSubset(of: capturedInPass)
        }
    }

    func isSessionComplete(capturedSlots: Set<Int>) -> Bool {
        isPassComplete(pass: .horizontal, capturedSlots: capturedSlots)
            && isPassComplete(pass: .elevated, capturedSlots: capturedSlots)
    }

    /// Coverage bins (0…7) for UI progress — works for both modes.
    func coveredSectorIndices(pass: CapturePass, capturedSlots: Set<Int>) -> Set<Int> {
        let capturedInPass = capturedSlots.compactMap { key -> Int? in
            let v = key - pass.rawValue * 100
            return (0..<CaptureConstants.viewsPerPass).contains(v) ? v : nil
        }
        var sectors = Set<Int>()
        for slot in capturedInPass {
            sectors.insert(sectorIndex(forSlot: slot))
        }
        return sectors
    }

    func missingSectorIndices(pass: CapturePass, capturedSlots: Set<Int>) -> [Int] {
        let covered = coveredSectorIndices(pass: pass, capturedSlots: capturedSlots)
        return (0..<8).filter { !covered.contains($0) }
    }

    func sectorIndex(forSlot slot: Int) -> Int {
        // 8 sectors of 45°; slot is 10° units.
        ((slot % CaptureConstants.viewsPerPass) / Self.adaptiveSectorStepSlots) % 8
    }

    /// Whether an optional fill should be requested after a required capture (quality weak / gap).
    func shouldRequestFill(
        afterRequiredSlot slot: Int,
        pass: CapturePass,
        capturedSlots: Set<Int>,
        lastQualityAccepted: Bool
    ) -> CaptureViewpoint? {
        guard mode == .adaptiveCoverage else { return nil }
        guard !lastQualityAccepted else { return nil }
        let fillSlot = (slot + Self.adaptiveFillStepSlots) % CaptureConstants.viewsPerPass
        let capturedInPass = Set(capturedSlots.compactMap { key -> Int? in
            let v = key - pass.rawValue * 100
            return (0..<CaptureConstants.viewsPerPass).contains(v) ? v : nil
        })
        guard !capturedInPass.contains(fillSlot) else { return nil }
        return CaptureViewpoint(
            slot: fillSlot,
            pass: pass,
            isRequired: false,
            label: ViewpointGuidance.label(forSlot: fillSlot, pass: pass)
        )
    }

    /// Associates a captured azimuth with the nearest planned viewpoint for the pass.
    func associate(azimuthDegrees: Double, pass: CapturePass) -> CaptureViewpoint? {
        let normalized = CapturedView.normalizeAzimuth(azimuthDegrees)
        let slot = Int((normalized / CaptureConstants.azimuthStepDegrees).rounded()) % CaptureConstants.viewsPerPass
        return viewpoints(for: pass).first { $0.slot == slot }
            ?? CaptureViewpoint(
                slot: slot,
                pass: pass,
                isRequired: mode == .classic72,
                label: ViewpointGuidance.label(forSlot: slot, pass: pass)
            )
    }
}

/// Plain-language viewpoint labels for non-photographer operators.
enum ViewpointGuidance {
    static func label(forSlot slot: Int, pass: CapturePass) -> String {
        let az = slot * Int(CaptureConstants.azimuthStepDegrees)
        let band = pass == .horizontal ? "side height" : "slightly above"
        let compass = compassName(azimuth: az)
        return "\(compass) · \(band)"
    }

    static func compassName(azimuth: Int) -> String {
        // 0° = front of dish at session start (operator-facing reference).
        switch ((azimuth % 360) + 360) % 360 {
        case 0..<23, 338...360: return "Front"
        case 23..<68: return "Front-right"
        case 68..<113: return "Right"
        case 113..<158: return "Back-right"
        case 158..<203: return "Back"
        case 203..<248: return "Back-left"
        case 248..<293: return "Left"
        default: return "Front-left"
        }
    }

    static func moveInstruction(degreesClockwise: Double, viewpoint: CaptureViewpoint) -> String {
        let deg = max(5, Int(abs(degreesClockwise).rounded()))
        return "Rotate dish ↻ ~\(deg)° → \(viewpoint.label)"
    }
}

/// User-facing tracking / permission messages (pure strings for testability).
enum CaptureTrackingMessages {
    static func cameraPermissionDenied() -> String {
        "Camera access is off. Enable Camera for AR Food in Settings, then return here."
    }

    static func motionUnavailable() -> String {
        "Motion sensors unavailable — elevation coaching is limited. Keep the phone still and use CAPTURE NEXT."
    }

    static func phoneMoving() -> String {
        "Phone is moving — freeze the phone. Rotate only the dish."
    }

    static func sessionInterrupted() -> String {
        "Capture was interrupted. Resume to continue from saved progress, or clear to start over."
    }

    static func backgroundedHint() -> String {
        "Progress saved. Resume when you return — no need to restart for a small pause."
    }
}
