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
    
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName
        case email
        case videosUploaded
        case createdAt
    }
    
    init(id: String = UUID().uuidString,
         username: String,
         displayName: String,
         email: String,
         videosUploaded: Int = 0,
         createdAt: Date = Date()) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.email = email
        self.videosUploaded = videosUploaded
        self.createdAt = createdAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        displayName = try container.decode(String.self, forKey: .displayName)
        email = try container.decode(String.self, forKey: .email)
        videosUploaded = try container.decode(Int.self, forKey: .videosUploaded)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(username, forKey: .username)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(email, forKey: .email)
        try container.encode(videosUploaded, forKey: .videosUploaded)
        try container.encode(createdAt, forKey: .createdAt)
    }
}
