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

// MARK: - Haptic Event

struct HapticEvent: Identifiable, Codable {
    var id: UUID = UUID()
    var time: Double
    var intensity: Float
    var sharpness: Float
    var duration: Double
    var type: HapticEventType
    
    init(id: UUID = UUID(), time: Double, intensity: Float, sharpness: Float, duration: Double, type: HapticEventType) {
        self.id = id
        self.time = time
        self.intensity = intensity
        self.sharpness = sharpness
        self.duration = duration
        self.type = type
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

// MARK: - CHHapticPattern Extension

extension HapticPattern {
    func toCHHapticPattern() throws -> CHHapticPattern {
        var chEvents: [CHHapticEvent] = []
        
        for event in events {
            let parameters: [CHHapticEventParameter] = [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: event.intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: event.sharpness)
            ]
            
            switch event.type {
            case .transient, .impact:
                chEvents.append(
                    CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: parameters,
                        relativeTime: event.time
                    )
                )
            case .continuous:
                chEvents.append(
                    CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: parameters,
                        relativeTime: event.time,
                        duration: event.duration
                    )
                )
            }
        }
        
        return try CHHapticPattern(events: chEvents, parameters: [])
    }
}

extension HapticEvent {
    func toCHHapticEvent() throws -> CHHapticEvent {
        let parameters: [CHHapticEventParameter] = [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
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

// MARK: - Curve Point (for automation lanes)

struct CurvePoint: Identifiable, Codable {
    var id: UUID = UUID()
    var time: Double
    var value: Float
    
    init(id: UUID = UUID(), time: Double, value: Float) {
        self.id = id
        self.time = time
        self.value = value
    }
}
