//
//  CloudDataStore.swift
//  HapticVideoApp
//
//  Supabase implementation for cloud storage and database.
//  Mirrors the original Firebase API surface so ViewModels need minimal changes.
//

import Foundation
import Supabase

final class CloudDataStore: VideoDataStore {
    static let shared = CloudDataStore()
    private init() {}

    // MARK: - Video Management

    /// Fetches the 50 most recent videos from the `videos` table.
    func fetchAllVideos() async throws -> [Video] {
        let videos: [Video] = try await supabase
            .from("videos")
            .select()
            .order("uploaded_at", ascending: false)
            .limit(50)
            .execute()
            .value
        return videos
    }

    /// Fetches a single video by its UUID string ID.
    func fetchVideo(byId id: String) async throws -> Video? {
        let video: Video = try await supabase
            .from("videos")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
        return video
    }

    /// Uploads video + thumbnail (+ optional haptics) to Supabase Storage,
    /// then inserts a row into the `videos` table.
    @discardableResult
    func uploadVideo(
        video: Video,
        videoData: Data,
        videoFileExtension: String,
        thumbnailData: Data,
        hapticsData: Data?
    ) async throws -> Video {

        // 1. Upload video file (original container extension preserved)
        let ext = videoFileExtension.isEmpty ? "mp4" : videoFileExtension
        let videoPath = "\(video.id).\(ext)"
        try await supabase.storage
            .from("videos")
            .upload(
                videoPath,
                data: videoData,
                options: FileOptions(contentType: ext == "mov" ? "video/quicktime" : "video/mp4", upsert: true)
            )
        let videoURL = try supabase.storage
            .from("videos")
            .getPublicURL(path: videoPath)
            .absoluteString

        // 2. Upload thumbnail
        let thumbPath = "\(video.id).jpg"
        try await supabase.storage
            .from("thumbnails")
            .upload(
                thumbPath,
                data: thumbnailData,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )
        let thumbnailURL = try supabase.storage
            .from("thumbnails")
            .getPublicURL(path: thumbPath)
            .absoluteString

        // 3. Optionally upload haptics JSON
        var hapticsURL: String? = nil
        if let hapticsData {
            let hapticsPath = "\(video.id).json"
            try await supabase.storage
                .from("haptics")
                .upload(
                    hapticsPath,
                    data: hapticsData,
                    options: FileOptions(contentType: "application/json", upsert: true)
                )
            hapticsURL = try supabase.storage
                .from("haptics")
                .getPublicURL(path: hapticsPath)
                .absoluteString
        }

        // 4. Insert metadata row
        var cloudVideo = video
        cloudVideo.videoURL    = videoURL
        cloudVideo.thumbnailURL = thumbnailURL
        cloudVideo.hapticsURL  = hapticsURL

        try await supabase
            .from("videos")
            .insert(cloudVideo)
            .execute()

        return cloudVideo
    }

    /// Atomically bumps the view counter (SQL: `update videos set views = views + 1`).
    /// Uses the `increment_views` RPC so concurrent viewers don't lose counts.
    func incrementViews(videoId: String) async throws {
        try await supabase
            .rpc("increment_views", params: ["p_video_id": videoId])
            .execute()
    }

    /// Deletes the storage objects and the metadata row for a video.
    func deleteVideo(_ video: Video) async throws {
        // Storage removal is best-effort; the row delete is what matters.
        let videoName = URL(string: video.videoURL)?.lastPathComponent ?? "\(video.id).mp4"
        _ = try? await supabase.storage.from("videos").remove(paths: [videoName])
        _ = try? await supabase.storage.from("thumbnails").remove(paths: ["\(video.id).jpg"])
        if video.hapticsURL != nil {
            _ = try? await supabase.storage.from("haptics").remove(paths: ["\(video.id).json"])
        }
        try await supabase
            .from("videos")
            .delete()
            .eq("id", value: video.id)
            .execute()
    }

    // MARK: - User Management

    /// Upserts a user profile row into the `users` table.
    func saveUserMetadata(_ user: User) {
        Task {
            do {
                try await supabase
                    .from("users")
                    .upsert(user)
                    .execute()
            } catch {
                print("❌ Failed to save user metadata: \(error)")
            }
        }
    }

}
