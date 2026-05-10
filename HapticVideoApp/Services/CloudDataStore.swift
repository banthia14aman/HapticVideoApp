//
//  CloudDataStore.swift
//  HapticVideoApp
//
//  Firebase implementation for cloud storage and Firestore database.
//  Note: Requires Firebase SDK to be added via Xcode (File -> Add Package Dependencies)
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage

class CloudDataStore {
    static let shared = CloudDataStore()
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    private init() {}
    
    // MARK: - Video Management
    
    /// Fetches all public videos from Firestore
    func fetchAllVideos(completion: @escaping ([Video]?, Error?) -> Void) {
        db.collection("videos")
            .order(by: "uploadedAt", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(nil, error)
                    return
                }
                
                let videos = snapshot?.documents.compactMap { doc -> Video? in
                    try? doc.data(as: Video.self)
                } ?? []
                
                completion(videos, nil)
            }
    }
    
    /// Fetches a specific video by ID (useful for shareable links)
    func fetchVideo(byId id: String, completion: @escaping (Video?, Error?) -> Void) {
        db.collection("videos").document(id).getDocument { snapshot, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            let video = try? snapshot?.data(as: Video.self)
            completion(video, nil)
        }
    }
    
    /// Uploads a video and its thumbnail/haptics to Firebase Storage, then saves metadata to Firestore
    func uploadVideo(video: Video, videoData: Data, thumbnailData: Data, hapticsData: Data?, completion: @escaping (Result<Video, Error>) -> Void) {
        
        let videoRef = storage.reference().child("videos/\(video.id).mp4")
        let thumbRef = storage.reference().child("thumbnails/\(video.id).jpg")
        
        // 1. Upload Video
        videoRef.putData(videoData, metadata: nil) { [weak self] _, error in
            if let error = error { return completion(.failure(error)) }
            
            videoRef.downloadURL { videoURL, error in
                if let error = error { return completion(.failure(error)) }
                guard let videoURLString = videoURL?.absoluteString else { return }
                
                // 2. Upload Thumbnail
                thumbRef.putData(thumbnailData, metadata: nil) { _, error in
                    if let error = error { return completion(.failure(error)) }
                    
                    thumbRef.downloadURL { thumbURL, error in
                        if let error = error { return completion(.failure(error)) }
                        guard let thumbURLString = thumbURL?.absoluteString else { return }
                        
                        var finalHapticsURL: String? = nil
                        
                        let dispatchGroup = DispatchGroup()
                        
                        // 3. Optional: Upload Haptics
                        if let hapticsData = hapticsData {
                            dispatchGroup.enter()
                            let hapticsRef = self?.storage.reference().child("haptics/\(video.id).json")
                            hapticsRef?.putData(hapticsData, metadata: nil) { _, error in
                                hapticsRef?.downloadURL { url, _ in
                                    finalHapticsURL = url?.absoluteString
                                    dispatchGroup.leave()
                                }
                            }
                        }
                        
                        dispatchGroup.notify(queue: .main) {
                            var cloudVideo = video
                            // Update the URLs to the remote cloud URLs
                            cloudVideo.videoURL = videoURLString
                            cloudVideo.thumbnailURL = thumbURLString
                            cloudVideo.hapticsURL = finalHapticsURL
                            
                            // 4. Save Metadata to Firestore
                            do {
                                try self?.db.collection("videos").document(cloudVideo.id).setData(from: cloudVideo)
                                completion(.success(cloudVideo))
                            } catch {
                                completion(.failure(error))
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - User Management
    
    func saveUserMetadata(_ user: User) {
        do {
            try db.collection("users").document(user.id).setData(from: user)
        } catch {
            print("❌ Failed to save user metadata: \(error)")
        }
    }
}
