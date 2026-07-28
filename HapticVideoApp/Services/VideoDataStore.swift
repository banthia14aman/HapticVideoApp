//
//  VideoDataStore.swift
//  HapticVideoApp
//
//  Single seam between the ViewModels and whichever backend is active.
//

import Foundation

protocol VideoDataStore {
    func fetchAllVideos() async throws -> [Video]
    func fetchVideo(byId id: String) async throws -> Video?
    @discardableResult
    func uploadVideo(video: Video, videoData: Data, videoFileExtension: String, thumbnailData: Data, hapticsData: Data?) async throws -> Video
    func incrementViews(videoId: String) async throws
    func deleteVideo(_ video: Video) async throws
    func saveUserMetadata(_ user: User)
    /// On-device footprint of stored media. Defaulted below so remote
    /// stores don't have to implement it; LocalDataStore overrides.
    func storageUsage() -> (videoCount: Int, bytes: Int64)
}

extension VideoDataStore {
    func storageUsage() -> (videoCount: Int, bytes: Int64) { (0, 0) }
}

enum AppBackend {
    /// ponytail: local-only for now. Flip to true once a Supabase project
    /// exists — run supabase/schema.sql there and set SupabaseConfig credentials.
    static let useCloud = false

    static var store: VideoDataStore {
        useCloud ? CloudDataStore.shared : LocalDataStore.shared
    }
}
