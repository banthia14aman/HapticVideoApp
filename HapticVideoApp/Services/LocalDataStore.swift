//
//  LocalDataStore.swift
//  HapticVideoApp
//

import Foundation

class LocalDataStore {
    static let shared = LocalDataStore()
    
    private let videosKey = "allVideos"
    private let currentUserKey = "currentUser"
    
    private init() {}
    
    // MARK: - Documents Directory
    
    func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    // MARK: - User Management
    
    func saveUser(_ user: User) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(user)
            UserDefaults.standard.set(data, forKey: currentUserKey)
            print("✅ User saved: \(user.username)")
        } catch {
            print("❌ Failed to save user: \(error)")
        }
    }
    
    func getCurrentUser() -> User? {
        guard let data = UserDefaults.standard.data(forKey: currentUserKey) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let user = try decoder.decode(User.self, from: data)
            return user
        } catch {
            print("❌ Failed to load user: \(error)")
            return nil
        }
    }
    
    func clearCurrentUser() {
        UserDefaults.standard.removeObject(forKey: currentUserKey)
        print("🗑️ User cleared")
    }
    
    func updateUserVideoCount(_ userId: String, increment: Int = 1) {
        guard var user = getCurrentUser(), user.id == userId else { return }
        user.videosUploaded += increment
        saveUser(user)
    }
    
    // MARK: - Video Management
    
    func saveVideo(_ video: Video) {
        var videos = getAllVideos()
        
        // Remove existing video with same ID (if updating)
        videos.removeAll { $0.id == video.id }
        
        // Add new video
        videos.append(video)
        
        // Save to UserDefaults
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(videos)
            UserDefaults.standard.set(data, forKey: videosKey)
            
            // Update user's video count
            updateUserVideoCount(video.uploaderID)
            
            print("✅ Video saved: \(video.title) (Total: \(videos.count))")
        } catch {
            print("❌ Failed to save video: \(error)")
        }
    }
    
    func getAllVideos() -> [Video] {
        guard let data = UserDefaults.standard.data(forKey: videosKey) else {
            return getMockVideos()
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let videos = try decoder.decode([Video].self, from: data)
            return videos.sorted { $0.uploadedAt > $1.uploadedAt }
        } catch {
            print("❌ Failed to load videos: \(error)")
            return getMockVideos()
        }
    }
    
    func getVideo(byId id: String) -> Video? {
        return getAllVideos().first { $0.id == id }
    }
    
    func deleteVideo(_ videoId: String) {
        var videos = getAllVideos()
        
        // Get video to delete (for file cleanup)
        if let video = videos.first(where: { $0.id == videoId }) {
            deleteFile(at: video.videoURL)
            deleteFile(at: video.thumbnailURL)
            if let hapticsURL = video.hapticsURL {
                deleteFile(at: hapticsURL)
            }
        }
        
        videos.removeAll { $0.id == videoId }
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(videos)
            UserDefaults.standard.set(data, forKey: videosKey)
            print("🗑️ Video deleted: \(videoId)")
        } catch {
            print("❌ Failed to delete video: \(error)")
        }
    }
    
    func incrementViews(for videoId: String) {
        var videos = getAllVideos()
        
        if let index = videos.firstIndex(where: { $0.id == videoId }) {
            videos[index].views += 1
            
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(videos)
                UserDefaults.standard.set(data, forKey: videosKey)
                print("👁️ Views incremented for: \(videos[index].title)")
            } catch {
                print("❌ Failed to update views: \(error)")
            }
        }
    }
    
    // MARK: - File Management
    
    private func deleteFile(at path: String) {
        let url = URL(fileURLWithPath: path)
        do {
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(at: url)
                print("🗑️ Deleted file: \(url.lastPathComponent)")
            }
        } catch {
            print("❌ Failed to delete file: \(error)")
        }
    }
    
    // MARK: - Mock Data
    
    private func getMockVideos() -> [Video] {
        return [
            Video(
                id: "mock1",
                title: "Sample Haptic Video 1",
                videoURL: "/mock/video1.mp4",
                thumbnailURL: "/mock/thumb1.jpg",
                uploaderID: "system",
                uploaderUsername: "System",
                uploadedAt: Date().addingTimeInterval(-86400),
                duration: 45.0,
                hasHaptics: true,
                hapticsURL: nil,
                views: 124,
                description: "Sample video with AI-generated haptics"
            ),
            Video(
                id: "mock2",
                title: "Sample Haptic Video 2",
                videoURL: "/mock/video2.mp4",
                thumbnailURL: "/mock/thumb2.jpg",
                uploaderID: "system",
                uploaderUsername: "System",
                uploadedAt: Date().addingTimeInterval(-172800),
                duration: 30.0,
                hasHaptics: true,
                hapticsURL: nil,
                views: 89,
                description: "Another haptic example"
            )
        ]
    }
    
    func clearAllData() {
        UserDefaults.standard.removeObject(forKey: videosKey)
        UserDefaults.standard.removeObject(forKey: currentUserKey)
        
        let documentsDir = getDocumentsDirectory()
        do {
            let files = try FileManager.default.contentsOfDirectory(at: documentsDir, includingPropertiesForKeys: nil)
            for file in files {
                try FileManager.default.removeItem(at: file)
            }
            print("🧹 All data cleared")
        } catch {
            print("❌ Failed to clear files: \(error)")
        }
    }
}
