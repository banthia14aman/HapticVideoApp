//
//  Video.swift
//  HapticVideoApp
//

import Foundation

struct Video: Identifiable, Codable {
    let id: String
    let title: String
    var videoURL: String
    var thumbnailURL: String
    let uploaderID: String
    let uploaderUsername: String
    let uploadedAt: Date
    let duration: Double
    let hasHaptics: Bool
    var hapticsURL: String?
    var views: Int
    let description: String?

    // Maps Swift camelCase to Supabase snake_case column names
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case duration
        case views
        case videoURL        = "video_url"
        case thumbnailURL    = "thumbnail_url"
        case uploaderID      = "uploader_id"
        case uploaderUsername = "uploader_username"
        case uploadedAt      = "uploaded_at"
        case hasHaptics      = "has_haptics"
        case hapticsURL      = "haptics_url"
    }

    init(id: String,
         title: String,
         videoURL: String,
         thumbnailURL: String,
         uploaderID: String,
         uploaderUsername: String,
         uploadedAt: Date,
         duration: Double,
         hasHaptics: Bool,
         hapticsURL: String?,
         views: Int,
         description: String?) {
        self.id               = id
        self.title            = title
        self.videoURL         = videoURL
        self.thumbnailURL     = thumbnailURL
        self.uploaderID       = uploaderID
        self.uploaderUsername = uploaderUsername
        self.uploadedAt       = uploadedAt
        self.duration         = duration
        self.hasHaptics       = hasHaptics
        self.hapticsURL       = hapticsURL
        self.views            = views
        self.description      = description
    }
}
