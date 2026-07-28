//
//  AHAPExporter.swift
//  HapticVideoApp
//
//  Exports HapticPattern to Apple's AHAP format.
//  AHAP schema reference: "Representing haptic patterns in AHAP files"
//  https://developer.apple.com/documentation/corehaptics/representing-haptic-patterns-in-ahap-files
//

import Foundation
import CoreHaptics

enum AHAPExporter {

    /// Core Haptics allows at most 16 control points per ParameterCurve.
    private static let maxCurvePoints = 16

    // MARK: - AHAP export

    static func exportAHAP(pattern: HapticPattern, title: String) -> URL? {
        // Top-level AHAP keys: "Version", "Metadata", "Pattern" (per Apple doc above).
        var patternEntries: [[String: Any]] = []

        for event in pattern.events.sorted(by: { $0.time < $1.time }) {
            let hasCurve = event.type == .continuous && !(event.intensityCurve?.isEmpty ?? true)

            // "Event" dict keys: "Time", "EventType", "EventDuration", "EventParameters"
            // with "ParameterID"/"ParameterValue" pairs.
            var eventDict: [String: Any] = [
                "Time": event.time,
                "EventParameters": [
                    // Curved events play at full base intensity; the ParameterCurve
                    // (envelope × gain) does the shaping — mirrors toCHHapticEvent().
                    ["ParameterID": "HapticIntensity", "ParameterValue": hasCurve ? 1.0 : Double(event.intensity)],
                    ["ParameterID": "HapticSharpness", "ParameterValue": Double(event.sharpness)]
                ]
            ]

            switch event.type {
            case .transient, .impact:
                eventDict["EventType"] = "HapticTransient"
            case .continuous:
                eventDict["EventType"] = "HapticContinuous"
                eventDict["EventDuration"] = event.duration
            }
            patternEntries.append(["Event": eventDict])

            // intensityCurve → "ParameterCurve" entries with "ParameterID",
            // "Time" (absolute), "ParameterCurveControlPoints" [{Time, ParameterValue}].
            if hasCurve, let curve = event.intensityCurve {
                let gain = Double(event.intensity)
                let points = curve.sorted { $0.time < $1.time }
                // Chunk into runs of ≤16 points (Core Haptics limit). Consecutive
                // curves share a boundary point so the envelope stays continuous.
                var start = 0
                while start < points.count {
                    let end = min(start + maxCurvePoints, points.count)
                    let chunk = points[start..<end]
                    let controlPoints: [[String: Any]] = chunk.map {
                        ["Time": $0.time - chunk.first!.time,
                         "ParameterValue": Double($0.value) * gain]
                    }
                    patternEntries.append(["ParameterCurve": [
                        "ParameterID": "HapticIntensityControl",
                        "Time": event.time + chunk.first!.time,
                        "ParameterCurveControlPoints": controlPoints
                    ]])
                    // ponytail: overlap last point as next chunk's first for continuity
                    start = end == points.count ? end : end - 1
                }
            }

            // sharpnessCurve → additive HapticSharpnessControl deltas against
            // the event's base sharpness (same semantics as live playback).
            if event.type == .continuous, let curve = event.sharpnessCurve, curve.count >= 2 {
                let base = Double(event.sharpness)
                let points = curve.sorted { $0.time < $1.time }
                var start = 0
                while start < points.count {
                    let end = min(start + maxCurvePoints, points.count)
                    let chunk = points[start..<end]
                    let controlPoints: [[String: Any]] = chunk.map {
                        ["Time": $0.time - chunk.first!.time,
                         "ParameterValue": max(-1, min(1, Double($0.value) - base))]
                    }
                    patternEntries.append(["ParameterCurve": [
                        "ParameterID": "HapticSharpnessControl",
                        "Time": event.time + chunk.first!.time,
                        "ParameterCurveControlPoints": controlPoints
                    ]])
                    start = end == points.count ? end : end - 1
                }
            }
        }

        let ahap: [String: Any] = [
            "Version": 1.0,
            "Metadata": [
                "Project": "HapticVideoApp",
                "Created": ISO8601DateFormatter().string(from: pattern.metadata.createdAt),
                "Description": title
            ],
            "Pattern": patternEntries
        ]

        guard JSONSerialization.isValidJSONObject(ahap),
              let data = try? JSONSerialization.data(withJSONObject: ahap, options: [.prettyPrinted, .sortedKeys])
        else { return nil }

        return write(data, name: sanitize(title) + ".ahap")
    }

    /// DEBUG-friendly round-trip check: does Core Haptics accept the file?
    static func validate(url: URL) -> Bool {
        (try? CHHapticPattern(contentsOf: url)) != nil
    }

    // MARK: - Native JSON export

    static func exportJSON(pattern: HapticPattern, title: String) -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(pattern) else { return nil }
        return write(data, name: sanitize(title) + ".json")
    }

    // MARK: - Helpers

    private static func sanitize(_ title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let cleaned = title.map { ch -> Character in
            ch.unicodeScalars.allSatisfy(allowed.contains) ? ch : "-"
        }
        let name = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return name.isEmpty ? "haptic-pattern" : name
    }

    private static func write(_ data: Data, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
