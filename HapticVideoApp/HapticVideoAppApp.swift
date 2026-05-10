//
//  HapticVideoAppApp.swift
//  HapticVideoApp
//

import SwiftUI
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct HapticVideoAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authViewModel = AuthenticationViewModel()
    @StateObject private var feedViewModel = FeedViewModel()
    
    @State private var sharedVideoToOpen: Video?
    @State private var showSharedVideo = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
                .environmentObject(feedViewModel)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .sheet(isPresented: $showSharedVideo) {
                    if let video = sharedVideoToOpen {
                        // Assuming VideoPlayerView can take a Video object
                        // VideoPlayerView(video: video)
                        Text("Playing Shared Video: \(video.title)")
                    }
                }
        }
    }
    
    private func handleDeepLink(_ url: URL) {
        // Example URL: hapticapp://video/12345
        // Or Universal Link: https://hapticvideoapp.com/v/12345
        
        let pathComponents = url.pathComponents
        if pathComponents.contains("video") || pathComponents.contains("v"), let id = pathComponents.last {
            feedViewModel.fetchSpecificVideo(byId: id) { video in
                if let video = video {
                    self.sharedVideoToOpen = video
                    self.showSharedVideo = true
                }
            }
        }
    }
}
