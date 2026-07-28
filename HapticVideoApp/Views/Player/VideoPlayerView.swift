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
    @State private var isScrubbing = false
    @State private var scrubTime: Double = 0
    @State private var isLiked = false
    @State private var heartBounce = false
    @State private var skipDirection: Int?
    @State private var exportItem: ExportItem?
    @AppStorage("likedVideos") private var likedVideosJSON = "[]"
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            // Video Player
            Color.black.ignoresSafeArea()
            
            if let player = playerManager.player {
                GeometryReader { geo in
                    // Bare AVPlayerLayer — SwiftUI's VideoPlayer ships its own
                    // tap-capturing control chrome, which swallowed taps on our
                    // custom buttons (close/like/share) and drew a second scrub
                    // bar + 10s skip buttons under ours.
                    PlayerLayerView(player: player)
                        .ignoresSafeArea()
                        .gesture(
                            SpatialTapGesture(count: 2)
                                .onEnded { value in
                                    skip(seconds: value.location.x > geo.size.width / 2 ? 5 : -5)
                                }
                                .exclusively(
                                    before: TapGesture().onEnded {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showControls.toggle()
                                        }
                                        resetControlsTimer()
                                    }
                                )
                        )
                }
                .ignoresSafeArea()

                // Skip indicator
                if let dir = skipDirection {
                    HStack {
                        if dir > 0 { Spacer() }
                        Image(systemName: dir > 0 ? "goforward.5" : "gobackward.5")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 72, height: 72)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                        if dir < 0 { Spacer() }
                    }
                    .padding(.horizontal, 44)
                    .transition(.opacity)
                    .allowsHitTesting(false)
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
            isLiked = likedVideoIDs().contains(video.id)
            resetControlsTimer()
        }
        .sheet(item: $exportItem) { item in
            ActivityShareSheet(items: [item.url])
        }
        .onDisappear {
            controlsTimer?.invalidate()
            playerManager.cleanup()
        }
        .fullScreenCover(isPresented: $showEditor) {
            if let pattern = playerManager.hapticPattern {
                HapticEditorView(
                    pattern: .constant(pattern),
                    videoURL: URL(string: video.videoURL) ?? URL(fileURLWithPath: video.videoURL),
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

            // Haptics A/B toggle — the "feel it / don't" comparison switch
            Button {
                UIHaptics.buttonTap()
                playerManager.hapticsEnabled.toggle()
            } label: {
                Image(systemName: playerManager.hapticsEnabled
                      ? "iphone.gen3.radiowaves.left.and.right"
                      : "iphone.gen3.slash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(playerManager.hapticsEnabled ? AppColors.primary : .white.opacity(0.6))
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
                ActionButton(
                    icon: isLiked ? "heart.fill" : "heart",
                    label: "Like",
                    tint: isLiked ? .red : .white
                ) {
                    toggleLike()
                }
                .scaleEffect(heartBounce ? 1.25 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.4), value: heartBounce)

                Spacer()

                // Share Button
                ShareLink(item: "Feel this video on HapticVideo — hapticapp://video/\(video.id)") {
                    VStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 22))
                        Text("Share")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white)
                }
                .simultaneousGesture(TapGesture().onEnded { UIHaptics.buttonTap() })

                Spacer()

                // Export Menu
                Menu {
                    Button {
                        exportAHAP()
                    } label: {
                        Label("Export AHAP", systemImage: "waveform.badge.plus")
                    }
                    .disabled(playerManager.hapticPattern == nil)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 22))
                        Text("More")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 20)

            // Scrub Bar
            HStack(spacing: 10) {
                Text(timeString(isScrubbing ? scrubTime : playerManager.currentTime))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.8))

                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubTime : playerManager.currentTime },
                        set: { scrubTime = $0; isScrubbing = true }
                    ),
                    in: 0...max(video.duration, 0.01),
                    onEditingChanged: { editing in
                        if !editing {
                            playerManager.seek(to: scrubTime)
                            isScrubbing = false
                        }
                        resetControlsTimer()
                    }
                )
                .tint(AppColors.primary)

                Text(timeString(video.duration))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }

    // MARK: - Helpers

    private func skip(seconds: Double) {
        UIHaptics.selectionChanged()
        playerManager.seek(to: playerManager.currentTime + seconds)
        withAnimation(.easeInOut(duration: 0.15)) {
            skipDirection = seconds > 0 ? 1 : -1
        }
        // ponytail: rapid taps may hide the indicator early; a token dance isn't worth it
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeInOut(duration: 0.2)) { skipDirection = nil }
        }
    }

    private func likedVideoIDs() -> Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: Data(likedVideosJSON.utf8))) ?? []
    }

    private func toggleLike() {
        var ids = likedVideoIDs()
        if isLiked {
            ids.remove(video.id)
            UIHaptics.buttonTap()
        } else {
            ids.insert(video.id)
            UIHaptics.success()
            heartBounce = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { heartBounce = false }
        }
        isLiked.toggle()
        if let data = try? JSONEncoder().encode(ids) {
            likedVideosJSON = String(decoding: data, as: UTF8.self)
        }
    }

    private func exportAHAP() {
        guard let pattern = playerManager.hapticPattern else { return }
        UIHaptics.buttonTapMedium()
        if let url = AHAPExporter.exportAHAP(pattern: pattern, title: video.title) {
            exportItem = ExportItem(url: url)
        } else {
            UIHaptics.error()
        }
    }

    private func timeString(_ time: Double) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let total = Int(time)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

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

/// Chrome-free video surface: just an AVPlayerLayer, no native controls.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    final class LayerHostView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerHostView {
        let view = LayerHostView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: LayerHostView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }
}

struct ActionButton: View {
    let icon: String
    let label: String
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(tint)
        }
    }
}

// MARK: - AHAP Export Share Sheet

private struct ExportItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Video Player Manager

@MainActor
class VideoPlayerManager: ObservableObject {
    @Published var player: AVPlayer?
    /// A/B switch: instantly compare the same clip with and without touch.
    @Published var hapticsEnabled = true {
        didSet {
            if hapticsEnabled {
                if player?.rate ?? 0 > 0 { startSyncedHaptics() }
            } else {
                hapticService.pauseAdvancedPlayer()
            }
        }
    }
    @Published var currentTime: Double = 0
    var hapticPattern: HapticPattern?

    private let hapticService = HapticService.shared
    private var timeObserver: Any?
    private var videoDuration: Double = 0
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var lastObservedTime: Double = 0

    private let stopHapticsBeforeEnd: Double = 1.0
    
    nonisolated func setup(video: Video) {
        Task { @MainActor in
            await setupPlayer(video: video)
        }
    }
    
    private func setupPlayer(video: Video) async {
        guard let videoURL = URL(string: video.videoURL) else {
            print("❌ Invalid video URL: \(video.videoURL)")
            return
        }
        let playerItem = AVPlayerItem(url: videoURL)
        player = AVPlayer(playerItem: playerItem)
        videoDuration = video.duration

        print("📹 Setting up player (duration: \(videoDuration)s)")
        
        if let hapticsPath = video.hapticsURL {
            await loadHaptics(from: hapticsPath, duration: video.duration)
        }
        
        // Advanced-player sync: the whole pattern is pre-scheduled on the
        // haptic server's clock (like the editor). The old 20ms polling path
        // fired events 30-70ms early with jitter and dropped them under
        // main-thread stalls.
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let currentTime = CMTimeGetSeconds(time)
                guard currentTime.isFinite else { return }

                // External seek → resync scheduled haptics to the new position.
                if abs(currentTime - self.lastObservedTime) > 0.5,
                   self.hapticsEnabled, (self.player?.rate ?? 0) > 0 {
                    self.startSyncedHaptics()
                }
                self.lastObservedTime = currentTime
                self.currentTime = currentTime
            }
        }

        statusObservation = player?.observe(\.rate, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if player.rate > 0 {
                    if self.hapticsEnabled { self.startSyncedHaptics() }
                } else {
                    self.hapticService.pauseAdvancedPlayer()
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hapticService.pauseAdvancedPlayer()
            }
        }
        
        player?.play()
        print("▶️ Playing")
    }
    
    func loadHaptics(from path: String, duration: Double) async {
        guard let url = URL(string: path) else {
            print("❌ Invalid haptics URL: \(path)")
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var pattern = try decoder.decode(HapticPattern.self, from: data)

            pattern.events = pattern.events.filter { event in
                event.time + event.duration <= duration - stopHapticsBeforeEnd
            }

            hapticPattern = pattern
            _ = hapticService.loadPattern(pattern.events)
            print("✅ Loaded \(pattern.events.count) haptic events (pre-scheduled)")

        } catch {
            print("❌ Failed to load haptics: \(error)")
        }
    }
    
    /// Seeks the pre-scheduled pattern to the live player clock and starts it.
    /// Reloads first if another screen's cleanup released the players.
    private func startSyncedHaptics() {
        guard let pattern = hapticPattern, !pattern.events.isEmpty else { return }
        if !hapticService.isPatternLoaded {
            _ = hapticService.loadPattern(pattern.events)
        }
        let t = player?.currentTime().seconds ?? 0
        guard t.isFinite, t < videoDuration - stopHapticsBeforeEnd else { return }
        hapticService.seekAdvancedPlayer(to: t)
        hapticService.startAdvancedPlayer()
    }

    /// Frame-accurate seek. The periodic observer's jump detector (>0.5s)
    /// resyncs the pre-scheduled haptics automatically.
    func seek(to time: Double) {
        let clamped = max(0, min(time, videoDuration))
        player?.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = clamped
    }

    func updateHaptics(pattern: HapticPattern) {
        self.hapticPattern = pattern
        _ = hapticService.loadPattern(pattern.events)
        if hapticsEnabled, (player?.rate ?? 0) > 0 { startSyncedHaptics() }
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

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
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
