//
//  HapticEditorViewModel.swift
//  HapticVideoApp
//
//  Uses CHHapticAdvancedPatternPlayer for proper video synchronization
//

import Foundation
import AVFoundation
import Combine

@MainActor
class HapticEditorViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var events: [HapticEvent] = []
    @Published var currentTime: Double = 0.0
    @Published var isPlaying: Bool = false
    @Published var showHapticEditor: Bool = false
    @Published var generatedPattern: HapticPattern?
    @Published var currentVideoURL: URL?
    
    // Video player
    @Published var player: AVPlayer?
    
    // Pattern and video info
    var videoDuration: Double
    private var videoURL: URL
    private var timeObserver: Any?
    private var rateObserver: NSKeyValueObservation?
    
    // Haptic playback
    private let hapticService = HapticService.shared
    private var hapticPatternLoaded: Bool = false
    private var lastSyncTime: Double = 0
    private let stopBeforeEnd: Double = 1.0 // Stop haptics 1 second before video ends
    
    init(pattern: HapticPattern, videoURL: URL, videoDuration: Double) {
        self.events = pattern.events
        self.videoURL = videoURL
        self.currentVideoURL = videoURL
        self.videoDuration = videoDuration
        self.generatedPattern = pattern
    }
    
    // MARK: - Video Player Setup
    
    func setupPlayer() {
        let playerItem = AVPlayerItem(url: videoURL)
        player = AVPlayer(playerItem: playerItem)
        
        // Preload haptic pattern
        loadHapticPattern()
        
        // Add time observer - high frequency for precise sync (20ms)
        let interval = CMTime(seconds: 0.02, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let currentTime = time.seconds
            self.currentTime = currentTime
            
            // Stop haptics before video ends
            if currentTime >= self.videoDuration - self.stopBeforeEnd {
                self.stopHapticsEarly()
            }
            
            // Detect large seeks (re-sync needed)
            let timeDiff = abs(currentTime - self.lastSyncTime)
            if timeDiff > 0.5 && self.isPlaying {
                self.hapticService.seekAdvancedPlayer(to: currentTime)
            }
            self.lastSyncTime = currentTime
        }
        
        // Observe play/pause state changes
        rateObserver = player?.observe(\.rate, options: [.new]) { [weak self] player, change in
            guard let self = self else { return }
            let playing = player.rate > 0
            
            Task { @MainActor in
                if playing && !self.isPlaying {
                    // Video started playing - sync haptics
                    self.syncHapticsToVideo()
                } else if !playing && self.isPlaying {
                    // Video paused - pause haptics
                    self.hapticService.pauseAdvancedPlayer()
                }
                self.isPlaying = playing
            }
        }
        
        // Listen for video end
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.handleVideoEnd()
        }
    }
    
    private func loadHapticPattern() {
        // Filter out events too close to end
        let safeEvents = events.filter { event in
            event.time + event.duration < videoDuration - stopBeforeEnd
        }
        
        hapticPatternLoaded = hapticService.loadPattern(safeEvents)
        
        if hapticPatternLoaded {
            print("✅ Haptic pattern loaded with \(safeEvents.count) events")
        } else {
            print("⚠️ Failed to load haptic pattern")
        }
    }
    
    private func syncHapticsToVideo() {
        guard hapticPatternLoaded else {
            loadHapticPattern()
            return
        }
        
        // Seek haptics to current video position and start
        hapticService.seekAdvancedPlayer(to: currentTime)
        hapticService.startAdvancedPlayer()
    }
    
    private func stopHapticsEarly() {
        if hapticService.isPlaying {
            hapticService.forceStopAllHaptics()
            print("🛑 Stopped haptics early (before video end)")
        }
    }
    
    func cleanup() {
        // Stop haptics first - FORCE stop to ensure they stop
        hapticService.forceStopAllHaptics()
        
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        rateObserver?.invalidate()
        rateObserver = nil
        player?.pause()
        player = nil
        hapticPatternLoaded = false
        NotificationCenter.default.removeObserver(self)
    }
    
    private func handleVideoEnd() {
        isPlaying = false
        hapticService.forceStopAllHaptics()
        hapticPatternLoaded = false
    }
    
    // MARK: - Playback Control
    
    func togglePlayPause() {
        if isPlaying {
            player?.pause()
            hapticService.pauseAdvancedPlayer()
            isPlaying = false
        } else {
            // Reload pattern if events were modified
            if !hapticPatternLoaded {
                loadHapticPattern()
            }
            player?.play()
            // Haptics will sync via rate observer
        }
    }
    
    func skipBackward() {
        let newTime = max(0, currentTime - 5.0)
        seek(to: newTime)
    }
    
    func skipForward() {
        let newTime = min(videoDuration - 1.0, currentTime + 5.0)
        seek(to: newTime)
    }
    
    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime)
        currentTime = time
        
        // Sync haptics to new position
        if hapticPatternLoaded {
            hapticService.seekAdvancedPlayer(to: time)
        }
    }
    
    // MARK: - Event Editing
    
    /// Call after editing events to reload the pattern
    func reloadHapticPattern() {
        hapticService.stopAdvancedPlayer()
        hapticPatternLoaded = false
        loadHapticPattern()
    }
    
    /// Preview a single haptic event (for testing)
    func previewEvent(_ event: HapticEvent) {
        var testEvent = event
        testEvent.duration = min(testEvent.duration, 0.3)
        hapticService.resetPlayedEvents()
        hapticService.playEvent(testEvent)
    }
}
