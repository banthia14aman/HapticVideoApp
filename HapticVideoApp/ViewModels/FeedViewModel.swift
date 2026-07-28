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

    private let dataStore = AppBackend.store

    func fetchVideos() {
        Task { await fetchVideosAsync() }
    }

    func fetchVideosAsync() async {
        isLoading = true
        errorMessage = nil

        do {
            let fetched = try await dataStore.fetchAllVideos()
            videos = fetched
            print("📹 Loaded \(fetched.count) videos from cloud")
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func fetchSpecificVideo(byId id: String, completion: @escaping (Video?) -> Void) {
        Task {
            do {
                let video = try await dataStore.fetchVideo(byId: id)
                completion(video)
            } catch {
                print("❌ Error fetching shared video: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }

    func incrementViews(for videoId: String) {
        // Optimistic local bump so the UI updates immediately.
        if let idx = videos.firstIndex(where: { $0.id == videoId }) {
            videos[idx].views += 1
        }
        Task {
            do { try await dataStore.incrementViews(videoId: videoId) }
            catch { print("⚠️ View increment failed: \(error.localizedDescription)") }
        }
    }

    func deleteVideo(_ video: Video) {
        Task {
            do {
                try await dataStore.deleteVideo(video)
                videos.removeAll { $0.id == video.id }
            } catch {
                errorMessage = "Delete failed: \(error.localizedDescription)"
            }
        }
    }
}
