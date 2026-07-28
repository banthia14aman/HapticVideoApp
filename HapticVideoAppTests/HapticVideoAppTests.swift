//
//  HapticVideoAppTests.swift
//  HapticVideoAppTests
//
//  Created by Aman Banthia on 12/12/25.
//

import Testing
import Foundation
@testable import HapticVideoApp

/// The models MUST encode to the snake_case column names the Supabase schema
/// uses (supabase/schema.sql) — a silent CodingKeys drift breaks every
/// fetch/insert without a compile error. These tests fail if that happens.
struct ModelCodingTests {

    @Test func videoEncodesToSupabaseColumnNames() throws {
        let video = Video(
            id: UUID().uuidString,
            title: "Test",
            videoURL: "https://x/video.mp4",
            thumbnailURL: "https://x/thumb.jpg",
            uploaderID: UUID().uuidString,
            uploaderUsername: "demo",
            uploadedAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 12.5,
            hasHaptics: true,
            hapticsURL: nil,
            views: 3,
            description: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(video)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["video_url"] as? String == video.videoURL)
        #expect(json["thumbnail_url"] as? String == video.thumbnailURL)
        #expect(json["uploader_id"] as? String == video.uploaderID)
        #expect(json["uploader_username"] as? String == video.uploaderUsername)
        #expect(json["has_haptics"] as? Bool == true)
        #expect(json["uploaded_at"] != nil)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(Video.self, from: data)
        #expect(back.id == video.id)
        #expect(back.videoURL == video.videoURL)
        #expect(back.duration == video.duration)
        #expect(back.views == video.views)
    }

    @Test func userEncodesToSupabaseColumnNames() throws {
        let user = User(username: "aman", displayName: "Aman", email: "a@b.c")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(user)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["display_name"] as? String == "Aman")
        #expect(json["videos_uploaded"] as? Int == 0)
        #expect(json["created_at"] != nil)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(User.self, from: data)
        #expect(back.username == user.username)
        #expect(back.displayName == user.displayName)
    }

    @Test func hapticPatternRoundTrips() throws {
        let pattern = HapticPattern(
            videoID: UUID().uuidString,
            events: [
                HapticEvent(time: 1.0, intensity: 0.8, sharpness: 0.5, duration: 0, type: .transient),
                HapticEvent(time: 2.5, intensity: 0.6, sharpness: 0.3, duration: 0.2, type: .continuous),
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let back = try decoder.decode(HapticPattern.self, from: encoder.encode(pattern))
        #expect(back.events.count == 2)
        #expect(back.events[0].type == .transient)
        #expect(back.events[1].duration == 0.2)
    }

    @Test func envelopeCurveRoundTripsAndOldJSONStillDecodes() throws {
        let curved = HapticEvent(
            time: 0.5, intensity: 1.0, sharpness: 0.2, duration: 2.0, type: .continuous,
            intensityCurve: [
                HapticCurvePoint(time: 0, value: 0.3),
                HapticCurvePoint(time: 1.0, value: 0.7),
                HapticCurvePoint(time: 2.0, value: 0.0),
            ]
        )

        let data = try JSONEncoder().encode(curved)
        let back = try JSONDecoder().decode(HapticEvent.self, from: data)
        #expect(back.intensityCurve?.count == 3)
        #expect(back.intensityCurve?[1].value == 0.7)

        // Sharpness sweep (engine RPM feel) round-trips too.
        var withSweep = curved
        withSweep.sharpnessCurve = [
            HapticCurvePoint(time: 0, value: 0.2),
            HapticCurvePoint(time: 2.0, value: 0.7),
        ]
        let sweepBack = try JSONDecoder().decode(
            HapticEvent.self, from: JSONEncoder().encode(withSweep))
        #expect(sweepBack.sharpnessCurve?.count == 2)
        #expect(sweepBack.sharpnessCurve?[1].value == 0.7)

        // Pre-curve JSON (no intensityCurve key) must still decode.
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","time":1.5,"intensity":0.8,"sharpness":0.5,"duration":0,"type":"transient"}
        """
        let legacy = try JSONDecoder().decode(HapticEvent.self, from: Data(legacyJSON.utf8))
        #expect(legacy.intensityCurve == nil)
        #expect(legacy.type == .transient)
    }
}
