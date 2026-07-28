//
//  HapticEventType.swift
//  HapticVideoApp
//
//  Created by Aman Banthia on 13/12/25.
//


//
//  HapticModels.swift
//  HapticVideoApp
//

import Foundation
import CoreHaptics

// MARK: - Haptic Event Type

enum HapticEventType: String, Codable, CaseIterable {
    case transient
    case impact
    case continuous
}

// MARK: - Haptic Curve Point

/// One control point of an intensity envelope, time relative to event start.
struct HapticCurvePoint: Codable, Equatable {
    var time: Double
    var value: Float
}

// MARK: - Haptic Event

struct HapticEvent: Identifiable, Codable {
    var id: UUID = UUID()
    var time: Double
    var intensity: Float
    var sharpness: Float
    var duration: Double
    var type: HapticEventType
    /// Waveform-following envelope for continuous events (nil = flat).
    /// `intensity` acts as a master gain over the curve.
    var intensityCurve: [HapticCurvePoint]?
    /// Frequency-feel sweep for continuous events (nil = static sharpness).
    /// Absolute target values; playback converts to additive deltas against
    /// `sharpness`. This is what makes an engine rev FEEL like rising RPM.
    var sharpnessCurve: [HapticCurvePoint]?

    init(id: UUID = UUID(), time: Double, intensity: Float, sharpness: Float,
         duration: Double, type: HapticEventType, intensityCurve: [HapticCurvePoint]? = nil,
         sharpnessCurve: [HapticCurvePoint]? = nil) {
        self.id = id
        self.time = time
        self.intensity = intensity
        self.sharpness = sharpness
        self.duration = duration
        self.type = type
        self.intensityCurve = intensityCurve
        self.sharpnessCurve = sharpnessCurve
    }
}

// MARK: - Haptic Pattern

struct HapticPattern: Identifiable, Codable {
    var id: String
    var videoID: String
    var events: [HapticEvent]
    var metadata: PatternMetadata
    
    init(id: String = UUID().uuidString, videoID: String, events: [HapticEvent] = [], metadata: PatternMetadata = PatternMetadata()) {
        self.id = id
        self.videoID = videoID
        self.events = events
        self.metadata = metadata
    }
    
    var isValid: Bool {
        !events.isEmpty
    }
}

// MARK: - Pattern Metadata

struct PatternMetadata: Codable {
    var createdAt: Date
    var updatedAt: Date
    var version: String
    
    init(createdAt: Date = Date(), updatedAt: Date = Date(), version: String = "1.0") {
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
    }
}

extension HapticEvent {
    func toCHHapticEvent() throws -> CHHapticEvent {
        // Curved continuous events play at full base intensity — the
        // pattern-level intensity curve (envelope × gain) does the shaping.
        let hasCurve = type == .continuous && !(intensityCurve?.isEmpty ?? true)
        let parameters: [CHHapticEventParameter] = [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: hasCurve ? 1.0 : intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
        ]
        
        switch type {
        case .transient, .impact:
            return CHHapticEvent(
                eventType: .hapticTransient,
                parameters: parameters,
                relativeTime: time
            )
        case .continuous:
            return CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: parameters,
                relativeTime: time,
                duration: duration
            )
        }
    }
}
