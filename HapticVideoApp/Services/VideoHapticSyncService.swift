//
//  VideoHapticSyncService.swift
//  HapticVideoApp
//

import Foundation
import AVFoundation

class VideoHapticSyncService: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var isPlaying: Bool = false
    
    private var videoPlayer: AVPlayer?
    private var hapticPattern: HapticPattern?
    private let hapticService = HapticService.shared
    private var timeObserver: Any?
    private var lastSyncTime: Double = 0
    private var playedEventIDs: Set<UUID> = []
    private var rateObservation: NSKeyValueObservation?
    
    init() {}
    
    // MARK: - Setup
    
    func setup(player: AVPlayer, pattern: HapticPattern) {
        self.videoPlayer = player
        self.hapticPattern = pattern
        setupSync()
    }
    
    private func setupSync() {
        guard let videoPlayer = videoPlayer else { return }
        
        // Monitor video time changes
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = videoPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] videoTime in
            guard let self = self else { return }
            let time = CMTimeGetSeconds(videoTime)
            self.currentTime = time
            self.handleTimeUpdate(time)
        }
        
        // Monitor play/pause using KVO
        rateObservation = videoPlayer.observe(\.rate, options: [.new]) { [weak self] player, change in
            guard let self = self else { return }
            let isPlaying = player.rate > 0
            self.handlePlaybackStateChange(isPlaying)
        }
    }
    
    private func handleTimeUpdate(_ videoTime: Double) {
        // Check for seeks (large time jumps)
        let timeDiff = abs(videoTime - lastSyncTime)
        if timeDiff > 1.0 {
            // User seeked - sync haptics to video time
            print("🔍 Seek detected, syncing haptics to \(String(format: "%.2f", videoTime))s")
            hapticService.seekHaptics(to: videoTime)
            playedEventIDs.removeAll() // Allow replaying events
        }
        
        // Play haptics at current time
        playHapticsAtCurrentTime(videoTime)
        
        lastSyncTime = videoTime
    }
    
    private func handlePlaybackStateChange(_ isPlaying: Bool) {
        self.isPlaying = isPlaying
        
        if isPlaying {
            if !hapticService.isPlaying {
                hapticService.resumeHaptics()
            }
        } else {
            if hapticService.isPlaying {
                hapticService.pauseHaptics()
            }
        }
    }
    
    // MARK: - Play Haptics at Current Time
    
    private func playHapticsAtCurrentTime(_ videoTime: Double) {
        guard let pattern = hapticPattern, isPlaying else { return }
        
        // Find haptic events that match current time (within 50ms window)
        let matchingEvents = pattern.events.filter { event in
            let eventTime = event.time
            return abs(eventTime - videoTime) < 0.05 && !playedEventIDs.contains(event.id)
        }
        
        for event in matchingEvents {
            hapticService.playEvent(event)
            playedEventIDs.insert(event.id)
        }
        
        // Clean up old IDs
        if playedEventIDs.count > 200 {
            playedEventIDs.removeAll()
        }
    }
    
    // MARK: - Reset
    
    func reset() {
        if let observer = timeObserver {
            videoPlayer?.removeTimeObserver(observer)
        }
        rateObservation?.invalidate()
        rateObservation = nil
        hapticService.stopAllHaptics()
        playedEventIDs.removeAll()
        lastSyncTime = 0
        videoPlayer = nil
        hapticPattern = nil
    }
    
    deinit {
        reset()
    }
}
