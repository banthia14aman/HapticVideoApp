//
//  User.swift
//  HapticVideoApp
//

import Foundation

struct User: Identifiable, Codable {
    let id: String
    let username: String
    let displayName: String
    let email: String
    var videosUploaded: Int
    let createdAt: Date

    // Maps Swift camelCase to Supabase snake_case column names
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case email
        case displayName    = "display_name"
        case videosUploaded = "videos_uploaded"
        case createdAt      = "created_at"
    }

    init(id: String = UUID().uuidString,
         username: String,
         displayName: String,
         email: String,
         videosUploaded: Int = 0,
         createdAt: Date = Date()) {
        self.id             = id
        self.username       = username
        self.displayName    = displayName
        self.email          = email
        self.videosUploaded = videosUploaded
        self.createdAt      = createdAt
    }
}
