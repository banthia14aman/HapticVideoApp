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
    
    private let dataStore = LocalDataStore.shared
    
    func fetchVideos() {
        isLoading = true
        errorMessage = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.videos = self?.dataStore.getAllVideos() ?? []
            self?.isLoading = false
            print("📹 Loaded \(self?.videos.count ?? 0) videos")
        }
    }
    
    func incrementViews(for videoId: String) {
        dataStore.incrementViews(for: videoId)
        videos = dataStore.getAllVideos()
    }
    
    func deleteVideo(_ videoId: String) {
        dataStore.deleteVideo(videoId)
        videos = dataStore.getAllVideos()
    }
}
