import Foundation

/// Display state for one coverage cell. Derived only from **accepted** photos + planner target.
enum CoverageCellState: String, Equatable {
    case completed
    case missing
    case targeted
}

struct CoverageMapCell: Equatable, Identifiable {
    let viewpoint: CaptureViewpoint
    let state: CoverageCellState

    var id: String { viewpoint.id }
    var isRequired: Bool { viewpoint.isRequired }
}

/// Compact coverage snapshot for one elevation pass. No separate counter — built from accepted slots.
struct CaptureCoverageMapSnapshot: Equatable {
    let pass: CapturePass
    let mode: CaptureSequenceMode
    let cells: [CoverageMapCell]

    var completedCount: Int { cells.filter { $0.state == .completed }.count }
    var requiredCount: Int { cells.filter(\.isRequired).count }
    var missingRequiredCount: Int {
        cells.filter { $0.isRequired && $0.state != .completed }.count
    }
    var targetedLabel: String? {
        cells.first(where: { $0.state == .targeted })?.viewpoint.label
    }

    var summaryText: String {
        if missingRequiredCount == 0 {
            return "\(pass.title): complete (\(completedCount) accepted)"
        }
        return "\(pass.title): \(completedCount)/\(requiredCount) required · \(missingRequiredCount) missing"
    }
}

enum CaptureCoverageMapBuilder {
    /// Builds map cells from **accepted** slot keys only (never “camera pointed at”).
    static func snapshot(
        mode: CaptureSequenceMode,
        pass: CapturePass,
        acceptedSlotKeys: Set<Int>,
        targetedSlot: Int?
    ) -> CaptureCoverageMapSnapshot {
        let planner = CaptureCoveragePlanner(mode: mode)
        let acceptedInPass = Set(acceptedSlotKeys.compactMap { key -> Int? in
            let v = key - pass.rawValue * 100
            return (0..<CaptureConstants.viewsPerPass).contains(v) ? v : nil
        })

        // Adaptive: required sectors only (8). Classic: every 10° required slot (36).
        let displayViewpoints: [CaptureViewpoint]
        switch mode {
        case .adaptiveCoverage:
            displayViewpoints = planner.requiredViewpoints(for: pass)
        case .classic72:
            displayViewpoints = planner.viewpoints(for: pass) // all required
        }

        let cells: [CoverageMapCell] = displayViewpoints.map { vp in
            let completed: Bool
            switch mode {
            case .classic72:
                completed = acceptedInPass.contains(vp.slot)
            case .adaptiveCoverage:
                // Sector complete when its required slot (or any accepted slot in that sector) exists.
                let sector = planner.sectorIndex(forSlot: vp.slot)
                completed = acceptedInPass.contains(where: { planner.sectorIndex(forSlot: $0) == sector })
            }

            let isTarget: Bool = {
                guard let targetedSlot, !completed else { return false }
                switch mode {
                case .classic72:
                    return targetedSlot == vp.slot
                case .adaptiveCoverage:
                    return planner.sectorIndex(forSlot: targetedSlot) == planner.sectorIndex(forSlot: vp.slot)
                }
            }()

            let state: CoverageCellState
            if completed {
                state = .completed
            } else if isTarget {
                state = .targeted
            } else {
                state = .missing
            }
            return CoverageMapCell(viewpoint: vp, state: state)
        }

        return CaptureCoverageMapSnapshot(pass: pass, mode: mode, cells: cells)
    }

    static func bothPasses(
        mode: CaptureSequenceMode,
        acceptedSlotKeys: Set<Int>,
        activePass: CapturePass,
        targetedSlot: Int?
    ) -> (horizontal: CaptureCoverageMapSnapshot, elevated: CaptureCoverageMapSnapshot) {
        let hTarget = activePass == .horizontal ? targetedSlot : nil
        let eTarget = activePass == .elevated ? targetedSlot : nil
        return (
            snapshot(mode: mode, pass: .horizontal, acceptedSlotKeys: acceptedSlotKeys, targetedSlot: hTarget),
            snapshot(mode: mode, pass: .elevated, acceptedSlotKeys: acceptedSlotKeys, targetedSlot: eTarget)
        )
    }
}

/// Pure review helpers — discard/retake impact without UIKit session.
enum CaptureReviewLogic {
    struct ReviewItem: Equatable, Identifiable {
        let slotKey: Int
        let azimuth: Double
        let elevation: Double
        let pass: CapturePass
        let label: String
        let qualityFlag: CaptureQualityIssue?
        let isRequired: Bool
        let frameIndex: Int

        var id: Int { slotKey }
        var hasQualityFlag: Bool { qualityFlag != nil }
    }

    static func orderedItems(
        mode: CaptureSequenceMode,
        frames: [RawCaptureFrame],
        slotKeysInOrder: [Int]
    ) -> [ReviewItem] {
        let planner = CaptureCoveragePlanner(mode: mode)
        var items: [ReviewItem] = []
        for (idx, key) in slotKeysInOrder.enumerated() {
            guard frames.indices.contains(idx) else { continue }
            let frame = frames[idx]
            let passIdx = key >= 100 ? 1 : 0
            let slot = key - passIdx * 100
            let pass = CapturePass(rawValue: passIdx) ?? .horizontal
            let vp = planner.viewpoints(for: pass).first { $0.slot == slot }
                ?? CaptureViewpoint(
                    slot: slot,
                    pass: pass,
                    isRequired: mode == .classic72,
                    label: ViewpointGuidance.label(forSlot: slot, pass: pass)
                )
            items.append(
                ReviewItem(
                    slotKey: key,
                    azimuth: frame.azimuth,
                    elevation: frame.elevation,
                    pass: pass,
                    label: vp.label,
                    qualityFlag: frame.qualityFlag,
                    isRequired: vp.isRequired,
                    frameIndex: idx
                )
            )
        }
        // Angular + elevation order: pass then azimuth.
        return items.sorted {
            if $0.pass.rawValue != $1.pass.rawValue {
                return $0.pass.rawValue < $1.pass.rawValue
            }
            return $0.azimuth < $1.azimuth
        }
    }

    /// Whether processing may proceed (required coverage from accepted slots).
    static func canProcess(mode: CaptureSequenceMode, acceptedSlotKeys: Set<Int>) -> Bool {
        CaptureCoveragePlanner(mode: mode).isSessionComplete(capturedSlots: acceptedSlotKeys)
    }

    /// Warning when discard would leave a required viewpoint uncovered.
    static func discardWarning(
        mode: CaptureSequenceMode,
        slotKey: Int,
        remainingSlotKeys: Set<Int>
    ) -> String? {
        let planner = CaptureCoveragePlanner(mode: mode)
        let passIdx = slotKey >= 100 ? 1 : 0
        let slot = slotKey - passIdx * 100
        let pass = CapturePass(rawValue: passIdx) ?? .horizontal
        let vp = planner.viewpoints(for: pass).first { $0.slot == slot }
        let isRequired: Bool = {
            guard let vp else { return mode == .classic72 }
            if mode == .adaptiveCoverage {
                // Required if this was the only accepted photo covering its sector.
                let sector = planner.sectorIndex(forSlot: slot)
                let stillCovered = remainingSlotKeys.contains { key in
                    let p = key >= 100 ? 1 : 0
                    guard p == passIdx else { return false }
                    let s = key - p * 100
                    return planner.sectorIndex(forSlot: s) == sector
                }
                return vp.isRequired && !stillCovered
            }
            return vp.isRequired
        }()

        guard isRequired else { return nil }
        let label = ViewpointGuidance.label(forSlot: slot, pass: pass)
        return "Discarding removes required coverage for \(label). Retake that angle before processing."
    }

    static func afterDiscard(
        mode: CaptureSequenceMode,
        slotKey: Int,
        frames: [RawCaptureFrame],
        slotKeysInOrder: [Int]
    ) -> (
        frames: [RawCaptureFrame],
        slotKeys: [Int],
        acceptedSlots: Set<Int>,
        warning: String?,
        canProcess: Bool
    ) {
        let result = CaptureRetakeLogic.retake(
            slotKey: slotKey,
            frames: frames,
            slotKeysInOrder: slotKeysInOrder
        )
        let warning = discardWarning(
            mode: mode,
            slotKey: slotKey,
            remainingSlotKeys: result.capturedSlots
        )
        let can = canProcess(mode: mode, acceptedSlotKeys: result.capturedSlots)
        return (result.frames, result.slotKeys, result.capturedSlots, warning, can)
    }
}
