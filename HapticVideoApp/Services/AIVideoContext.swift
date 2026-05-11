//
//  AIVideoContext.swift
//  HapticVideoApp
//
//  Bundles the outputs of the Phase-1 AI analyzers so they can be passed
//  to AudioAnalyzer as a semantic filter.
//

import Foundation

struct AIVideoContext: Sendable {
    let soundHits: [SoundHit]
    let motionSamples: [MotionSample]
    let videoDuration: Double

    static let empty = AIVideoContext(soundHits: [], motionSamples: [], videoDuration: 0)

    // MARK: - Sound queries

    /// True if any classifier window containing `time` has a label whose
    /// identifier contains `pattern` (case-insensitive) at ≥ `minConfidence`.
    func isLabelActive(matching pattern: String,
                       at time: Double,
                       minConfidence: Double = 0.5) -> Bool {
        let lower = pattern.lowercased()
        return soundHits.contains { hit in
            hit.confidence >= minConfidence
                && time >= hit.time
                && time <= hit.endTime
                && hit.label.lowercased().contains(lower)
        }
    }

    /// Returns an impact class active at `time` (gunshot / explosion / glass /
    /// slam), or nil. Used to upgrade event type & intensity.
    func matchingImpactClass(at time: Double, minConfidence: Double = 0.5) -> ImpactClass? {
        for impact in ImpactClass.allCases {
            for pattern in impact.labelPatterns {
                if isLabelActive(matching: pattern, at: time, minConfidence: minConfidence) {
                    return impact
                }
            }
        }
        return nil
    }

    // MARK: - Motion queries

    /// (mean, std) of motion magnitudes. Returns (0,0) for empty samples.
    func motionStats() -> (mean: Float, std: Float) {
        guard !motionSamples.isEmpty else { return (0, 0) }
        let mags = motionSamples.map { $0.magnitude }
        let mean = mags.reduce(0, +) / Float(mags.count)
        let variance = mags.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(mags.count)
        return (mean, sqrtf(variance))
    }
}

// MARK: - Impact class taxonomy

enum ImpactClass: CaseIterable, Sendable {
    case gunshot
    case explosion
    case glass
    case slam

    /// Substrings to match against the SNClassifier identifier
    /// (e.g. "gunshot_gunfire", "boom", "glass", "thud").
    var labelPatterns: [String] {
        switch self {
        case .gunshot:   return ["gunshot", "gunfire"]
        case .explosion: return ["explosion", "boom", "blast"]
        case .glass:     return ["glass", "shatter"]
        case .slam:      return ["slam", "crash", "thud"]
        }
    }

    /// What event type should we emit when this impact class fires?
    var preferredType: HapticEventType {
        switch self {
        case .glass:                       return .transient
        case .gunshot, .explosion, .slam:  return .impact
        }
    }

    /// Multiplier applied to base intensity when this class is detected.
    var intensityBoost: Float {
        switch self {
        case .gunshot:   return 1.5
        case .explosion: return 1.6
        case .glass:     return 1.4
        case .slam:      return 1.3
        }
    }
}
