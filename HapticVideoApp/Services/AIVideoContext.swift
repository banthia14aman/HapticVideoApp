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

    /// True when music-like content (music, singing) is active at `time`.
    /// INTEGRATION: AudioAnalyzer could use this to relax dialogue-suppression
    /// during music (sung vocals classify as speech-adjacent but should
    /// still produce haptics).
    func isMusicActive(at time: Double, minConfidence: Double = 0.5) -> Bool {
        return isLabelActive(matching: "music", at: time, minConfidence: minConfidence)
            || isLabelActive(matching: "singing", at: time, minConfidence: minConfidence)
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

// Ordered by priority: matchingImpactClass returns the FIRST active case,
// so big cinematic impacts come before drum/foley classes, and broad
// patterns ("engine") come last.
enum ImpactClass: CaseIterable, Sendable {
    case gunshot
    case explosion
    case fireworks
    case thunder
    case glass
    case slam
    case bassDrum
    case snareDrum
    case hiHat
    case clap
    case splash
    case footsteps
    case engine

    /// Substrings to match against the SNClassifier identifier
    /// (e.g. "gunshot_gunfire", "boom", "glass", "thud").
    var labelPatterns: [String] {
        switch self {
        case .gunshot:   return ["gunshot", "gunfire"]
        case .explosion: return ["explosion", "boom", "blast"]
        case .fireworks: return ["firework", "firecracker"]
        case .thunder:   return ["thunder"]
        case .glass:     return ["glass", "shatter"]
        case .slam:      return ["slam", "crash", "thud", "knock"]
        case .bassDrum:  return ["bass_drum", "kick_drum"]
        case .snareDrum: return ["snare_drum"]
        case .hiHat:     return ["hi-hat", "hi_hat", "cymbal"]
        case .clap:      return ["clapping", "applause"]
        case .splash:    return ["splash"]
        case .footsteps: return ["footsteps"]
        case .engine:    return ["engine_accelerating", "engine"]
        }
    }

    /// What event type should we emit when this impact class fires?
    var preferredType: HapticEventType {
        switch self {
        case .glass, .snareDrum, .hiHat, .clap, .splash, .footsteps:
            return .transient
        case .gunshot, .explosion, .fireworks, .thunder, .slam, .bassDrum:
            return .impact
        case .engine:
            // INTEGRATION: analyzer's impact-upgrade branch sets type but not
            // duration — a .continuous upgrade needs a nonzero duration there.
            return .continuous
        }
    }

    /// Multiplier applied to base intensity when this class is detected.
    var intensityBoost: Float {
        switch self {
        case .gunshot:   return 1.5
        case .explosion: return 1.6
        case .fireworks: return 1.4
        case .thunder:   return 1.5
        case .glass:     return 1.4
        case .slam:      return 1.3
        case .bassDrum:  return 1.2   // deep impact
        case .snareDrum: return 1.1   // sharp transient
        case .hiHat:     return 0.7   // light tick
        case .clap:      return 1.1
        case .splash:    return 1.1
        case .footsteps: return 1.0
        case .engine:    return 1.3   // continuous boost
        }
    }

    /// Sharpness the analyzer COULD apply when this class fires
    /// (nil = keep the spectrally-derived sharpness).
    /// INTEGRATION: AudioAnalyzer.generateHapticEvents currently ignores
    /// this; wire it into the impact-upgrade branch when desired.
    var preferredSharpness: Float? {
        switch self {
        case .gunshot:   return 0.7   // punch perception peaks ≈0.73
        case .explosion: return 0.2
        case .thunder:   return 0.15
        case .glass:     return 0.9
        case .bassDrum:  return 0.25
        case .snareDrum: return 0.7
        case .hiHat:     return 0.9
        case .engine:    return 0.2
        default:         return nil
        }
    }
}
