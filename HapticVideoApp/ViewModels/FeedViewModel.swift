//
//  FeedViewModel.swift
//  HapticVideoApp
//

import Foundation

@MainActor
class FeedViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Uses Firebase backend
    private let dataStore = CloudDataStore.shared
    
    func fetchVideos() {
        Task { await fetchVideosAsync() }
    }

    func fetchVideosAsync() async {
        isLoading = true
        errorMessage = nil

        await withCheckedContinuation { continuation in
            dataStore.fetchAllVideos { [weak self] fetchedVideos, error in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    if let error = error {
                        self?.errorMessage = error.localizedDescription
                    } else if let fetchedVideos = fetchedVideos {
                        self?.videos = fetchedVideos
                        print("📹 Loaded \(fetchedVideos.count) videos from cloud")
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    func fetchSpecificVideo(byId id: String, completion: @escaping (Video?) -> Void) {
        dataStore.fetchVideo(byId: id) { video, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error fetching shared video: \(error.localizedDescription)")
                    completion(nil)
                } else {
                    completion(video)
                }
            }
        }
    }
    
    func incrementViews(for videoId: String) {
        // Implement Firestore view increment here (e.g., FieldValue.increment(Int64(1)))
    }
    
    func deleteVideo(_ videoId: String) {
        // Implement Firestore/Storage deletion here
    }
}
