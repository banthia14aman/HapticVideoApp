//
//  VideoPlayerView.swift
//  HapticVideoApp
//
//  Modern 2025 video player with haptic sync and immersive controls
//

import SwiftUI
import AVKit
import AVFoundation

struct VideoPlayerView: View {
    let video: Video
    @StateObject private var playerManager = VideoPlayerManager()
    @State private var showEditor = false
    @State private var showControls = true
    @State private var controlsTimer: Timer?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            // Video Player
            Color.black.ignoresSafeArea()
            
            if let player = playerManager.player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showControls.toggle()
                        }
                        resetControlsTimer()
                    }
            } else {
                // Loading State
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppColors.primary))
                        .scaleEffect(1.5)
                    
                    Text("Loading video...")
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            
            // Controls Overlay
            if showControls {
                controlsOverlay
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .statusBar(hidden: !showControls)
        .onAppear {
            UIHaptics.prepare()
            playerManager.setup(video: video)
            resetControlsTimer()
        }
        .onDisappear {
            controlsTimer?.invalidate()
            playerManager.cleanup()
        }
        .fullScreenCover(isPresented: $showEditor) {
            if let pattern = playerManager.hapticPattern {
                HapticEditorView(
                    pattern: .constant(pattern),
                    videoURL: URL(fileURLWithPath: video.videoURL),
                    videoDuration: video.duration,
                    onSave: { editedPattern in
                        playerManager.updateHaptics(pattern: editedPattern)
                        showEditor = false
                    }
                )
            }
        }
    }
    
    // MARK: - Controls Overlay
    
    private var controlsOverlay: some View {
        ZStack {
            // Gradient backgrounds
            VStack {
                // Top gradient
                LinearGradient(
                    colors: [.black.opacity(0.7), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                
                Spacer()
                
                // Bottom gradient
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 140)
            }
            .ignoresSafeArea()
            
            // Controls
            VStack {
                // Top Bar
                topBar
                    .padding(.top, 8)
                
                Spacer()
                
                // Bottom Bar
                bottomBar
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack {
            // Close Button
            Button {
                UIHaptics.buttonTap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            
            Spacer()
            
            // Video Title
            VStack(spacing: 2) {
                Text(video.title)
                    .font(AppTypography.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(video.uploaderUsername)
                    .font(AppTypography.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            // More Options
            Button {
                UIHaptics.buttonTap()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
        }
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBar: some View {
        VStack(spacing: 16) {
            // Haptic Badge
            if video.hasHaptics {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 12, weight: .semibold))
                    
                    Text("Haptic Feedback Active")
                        .font(.system(size: 12, weight: .medium))
                    
                    Spacer()
                    
                    // Edit Button
                    Button {
                        UIHaptics.buttonTapMedium()
                        showEditor = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 11))
                            Text("Edit")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(AppColors.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppColors.primary.opacity(0.2))
                        .cornerRadius(12)
                    }
                }
                .foregroundColor(.white)
                .padding(12)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
            }
            
            // Action Buttons
            HStack(spacing: 20) {
                // Like Button
                ActionButton(icon: "heart", label: "Like") {
                    UIHaptics.buttonTap()
                }
                
                Spacer()
                
                // Share Button
                ActionButton(icon: "square.and.arrow.up", label: "Share") {
                    UIHaptics.buttonTap()
                }
                
                Spacer()
                
                // Download Button
                ActionButton(icon: "arrow.down.circle", label: "Save") {
                    UIHaptics.buttonTap()
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Helpers
    
    private func resetControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                showControls = false
            }
        }
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.white)
        }
    }
}

// MARK: - Video Player Manager

@MainActor
class VideoPlayerManager: ObservableObject {
    @Published var player: AVPlayer?
    var hapticPattern: HapticPattern?
    
    private let hapticService = HapticService.shared
    private var timeObserver: Any?
    private var playedEventIDs: Set<UUID> = []
    private var videoDuration: Double = 0
    private var statusObservation: NSKeyValueObservation?
    private var hasStoppedHaptics = false
    
    private let hapticLatency: Double = 0.05
    private let stopHapticsBeforeEnd: Double = 1.0
    
    nonisolated func setup(video: Video) {
        Task { @MainActor in
            await setupPlayer(video: video)
        }
    }
    
    private func setupPlayer(video: Video) async {
        let videoURL = URL(fileURLWithPath: video.videoURL)
        let playerItem = AVPlayerItem(url: videoURL)
        player = AVPlayer(playerItem: playerItem)
        videoDuration = video.duration
        hasStoppedHaptics = false
        
        print("📹 Setting up player (duration: \(videoDuration)s)")
        
        if let hapticsPath = video.hapticsURL {
            loadHaptics(from: hapticsPath, duration: video.duration)
        }
        
        let interval = CMTime(seconds: 0.02, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let currentTime = CMTimeGetSeconds(time)
                
                if currentTime >= self.videoDuration - self.stopHapticsBeforeEnd && !self.hasStoppedHaptics {
                    self.hapticService.forceStopAllHaptics()
                    self.hasStoppedHaptics = true
                    return
                }
                
                if !self.hasStoppedHaptics {
                    self.playHapticAt(time: currentTime)
                }
            }
        }
        
        statusObservation = player?.observe(\.rate, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if player.rate == 0 {
                    self.hapticService.forceStopAllHaptics()
                    self.playedEventIDs.removeAll()
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hapticService.forceStopAllHaptics()
                self?.hasStoppedHaptics = true
                self?.playedEventIDs.removeAll()
            }
        }
        
        player?.play()
        print("▶️ Playing")
    }
    
    func loadHaptics(from path: String, duration: Double) {
        do {
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var pattern = try decoder.decode(HapticPattern.self, from: data)
            
            pattern.events = pattern.events.filter { event in
                event.time + event.duration <= duration - stopHapticsBeforeEnd
            }
            
            hapticPattern = pattern
            print("✅ Loaded \(pattern.events.count) haptic events")
            
        } catch {
            print("❌ Failed to load haptics: \(error)")
        }
    }
    
    func playHapticAt(time: Double) {
        guard let pattern = hapticPattern else { return }
        guard let player = player, player.rate > 0 else { return }
        
        let lookAheadTime = time + hapticLatency
        
        let matchingEvents = pattern.events.filter { event in
            abs(event.time - lookAheadTime) < 0.03 && !playedEventIDs.contains(event.id)
        }
        
        for event in matchingEvents {
            hapticService.playEvent(event)
            playedEventIDs.insert(event.id)
        }
        
        if playedEventIDs.count > 150 {
            let eventsToKeep = pattern.events
                .filter { $0.time >= time - 2.0 }
                .map { $0.id }
            playedEventIDs = Set(eventsToKeep)
        }
    }
    
    func updateHaptics(pattern: HapticPattern) {
        self.hapticPattern = pattern
        playedEventIDs.removeAll()
        hasStoppedHaptics = false
    }
    
    func cleanup() {
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        statusObservation?.invalidate()
        statusObservation = nil
        
        player?.pause()
        player = nil
        
        hapticService.forceStopAllHaptics()
        playedEventIDs.removeAll()
        
        NotificationCenter.default.removeObserver(self)
    }
}

#Preview {
    VideoPlayerView(video: Video(
        id: "preview-1",
        title: "Test Video",
        videoURL: "/path/to/video.mov",
        thumbnailURL: "/path/to/thumb.jpg",
        uploaderID: "user1",
        uploaderUsername: "demo",
        uploadedAt: Date(),
        duration: 30,
        hasHaptics: true,
        hapticsURL: nil,
        views: 0,
        description: nil
    ))
}
