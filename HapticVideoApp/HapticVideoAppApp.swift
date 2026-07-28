//
//  HapticVideoAppApp.swift
//  HapticVideoApp
//

import SwiftUI

@main
struct HapticVideoAppApp: App {
    @StateObject private var authViewModel = AuthenticationViewModel()
    @StateObject private var feedViewModel = FeedViewModel()
    @Environment(\.scenePhase) private var scenePhase

    // ponytail: item-based sheet — no separate bool, sheet can never present with a nil video
    @State private var sharedVideoToOpen: Video?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
                .environmentObject(feedViewModel)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .sheet(item: $sharedVideoToOpen) { video in
                    VideoPlayerView(video: video)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        NotificationCenter.default.post(name: Notification.Name("app.background"), object: nil)
                    }
                }
        }
    }

    // Handles hapticapp://video/<id> and https://hapticvideoapp.com/v/<id>
    private func handleDeepLink(_ url: URL) {
        let parts = url.pathComponents.filter { $0 != "/" }
        let id: String?
        if url.host == "video" || url.host == "v" {
            id = parts.first
        } else if let i = parts.firstIndex(where: { $0 == "video" || $0 == "v" }), i + 1 < parts.count {
            id = parts[i + 1]
        } else {
            id = nil
        }
        guard let id, !id.isEmpty else { return }
        feedViewModel.fetchSpecificVideo(byId: id) { video in
            if let video {
                sharedVideoToOpen = video
                UIHaptics.buttonTapMedium()
            }
        }
    }
}
