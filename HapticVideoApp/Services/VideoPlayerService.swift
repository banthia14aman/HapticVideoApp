//
//  VideoPlayerService.swift
//  HapticVideoApp
//
//  Enhanced video player with haptic sync
//

import Foundation
import AVFoundation
import Combine

@MainActor
class VideoPlayerService: ObservableObject {
    @Published var currentTime: Double = 0.0
    @Published var duration: Double = 0.0
    @Published var isPlaying = false
    @Published var loadError: String?
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var statusObserver: AnyCancellable?
    
    var avPlayer: AVPlayer? {
        return player
    }
    
    // MARK: - Load Video
    
    func loadVideo(url: URL) {
        cleanup()

        if url.isFileURL {
            guard FileManager.default.fileExists(atPath: url.path) else {
                loadError = "Video file not found: \(url.lastPathComponent)"
                print("❌ Video file doesn't exist: \(url.path)")
                return
            }
        }

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        
        // Observe status
        statusObserver = playerItem.publisher(for: \.status)
            .sink { [weak self] status in
                switch status {
                case .readyToPlay:
                    print("✅ Video ready to play")
                    self?.loadError = nil
                case .failed:
                    let error = playerItem.error?.localizedDescription ?? "Unknown error"
                    self?.loadError = "Video load failed: \(error)"
                    print("❌ Video failed to load: \(error)")
                case .unknown:
                    print("⏳ Video loading...")
                @unknown default:
                    break
                }
            }
        
        // Observe duration
        playerItem.publisher(for: \.duration)
            .sink { [weak self] duration in
                let seconds = CMTimeGetSeconds(duration)
                if seconds.isFinite && seconds > 0 {
                    self?.duration = seconds
                    print("📹 Video duration: \(String(format: "%.2f", seconds))s")
                }
            }
            .store(in: &cancellables)
        
        // Observe current time
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = CMTimeGetSeconds(time)
            if seconds.isFinite {
                self?.currentTime = seconds
            }
        }
        
        // Observe playback rate
        player?.publisher(for: \.rate)
            .sink { [weak self] rate in
                self?.isPlaying = rate > 0
            }
            .store(in: &cancellables)
        
        // Observe end of playback
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            .sink { [weak self] _ in
                print("📹 Video finished")
                self?.isPlaying = false
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Playback Control
    
    func play() {
        guard let player = player else {
            print("⚠️ Cannot play: no player")
            return
        }
        player.play()
        print("▶️ Video playing")
    }
    
    func pause() {
        guard let player = player else { return }
        player.pause()
        print("⏸️ Video paused")
    }
    
    func seek(to time: Double) {
        guard let player = player else { return }
        let clampedTime = max(0, min(time, duration))
        let cmTime = CMTime(seconds: clampedTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        print("⏩ Video seeked to \(String(format: "%.2f", clampedTime))s")
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        player?.pause()
        player = nil
        cancellables.removeAll()
        statusObserver?.cancel()
        currentTime = 0.0
        duration = 0.0
        isPlaying = false
        print("🧹 Video player cleaned up")
    }
    
    // No deinit - let Swift handle automatic cleanup
    // The player will be deallocated automatically
}
