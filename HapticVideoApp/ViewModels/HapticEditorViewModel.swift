//
//  HapticEditorViewModel.swift
//  HapticVideoApp
//
//  Owns the AVPlayer + CHHapticAdvancedPatternPlayer pairing for the editor.
//  Designed to keep haptics tightly synchronized with the video timeline and
//  to recover cleanly from edits, seeks, and end-of-video.
//

import Foundation
import AVFoundation
import Combine
import UIKit

@MainActor
class HapticEditorViewModel: ObservableObject {
    // MARK: - Published State
    @Published var events: [HapticEvent] = []
    @Published var currentTime: Double = 0.0
    @Published var isPlaying: Bool = false
    @Published var thumbnails: [UIImage] = []
    @Published var showHapticEditor: Bool = false
    @Published var generatedPattern: HapticPattern?
    @Published var currentVideoURL: URL?

    // Video player
    @Published var player: AVPlayer?

    // Configuration
    let videoDuration: Double
    private let videoURL: URL
    private let stopBeforeEnd: Double = 0.5  // freeze playback / haptics this far from end

    // Internal observers
    private var timeObserver: Any?
    private var rateObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    // Haptic engine
    private let hapticService = HapticService.shared
    private var hapticPatternLoaded: Bool = false
    private var lastObservedTime: Double = 0
    private var lastReloadStamp: Date = .distantPast
    private let reloadDebounce: TimeInterval = 0.12

    init(pattern: HapticPattern, videoURL: URL, videoDuration: Double) {
        self.events = pattern.events
        self.videoURL = videoURL
        self.currentVideoURL = videoURL
        self.videoDuration = videoDuration
        self.generatedPattern = pattern
    }

    // MARK: - Video Player Setup

    func setupPlayer() {
        let asset = AVURLAsset(url: videoURL)
        let playerItem = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.actionAtItemEnd = .pause
        player = newPlayer

        loadHapticPattern()

        // 30Hz UI updates — smooth playhead without thrashing SwiftUI
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let t = time.seconds
            guard t.isFinite else { return }

            self.currentTime = t

            // Pull haptics down before the very end of the file
            if t >= self.videoDuration - self.stopBeforeEnd, self.hapticService.isPlaying {
                self.hapticService.pauseAdvancedPlayer()
            }
            self.lastObservedTime = t
        }

        // Rate observer: keep haptics in lockstep with the AVPlayer
        rateObserver = newPlayer.observe(\.rate, options: [.new]) { [weak self] avPlayer, _ in
            guard let self = self else { return }
            let isNowPlaying = avPlayer.rate > 0

            Task { @MainActor in
                guard isNowPlaying != self.isPlaying else { return }
                self.isPlaying = isNowPlaying
                if isNowPlaying {
                    self.startHapticPlayback()
                } else {
                    self.hapticService.pauseAdvancedPlayer()
                }
            }
        }

        // End-of-video reset
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleVideoEnd()
            }
        }

        Task {
            await generateThumbnails(asset: asset)
        }
    }

    // MARK: - Thumbnails for the video track

    private func generateThumbnails(asset: AVURLAsset) async {
        let count = max(8, min(24, Int(videoDuration / 2)))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 90)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        var images: [UIImage] = []
        for i in 0..<count {
            let t = Double(i) / Double(max(1, count - 1)) * videoDuration
            let cmTime = CMTime(seconds: t, preferredTimescale: 600)
            do {
                let cg = try await generator.image(at: cmTime).image
                images.append(UIImage(cgImage: cg))
            } catch {
                continue
            }
        }
        let finalImages = images
        await MainActor.run {
            self.thumbnails = finalImages
        }
    }

    // MARK: - Haptic Pattern Lifecycle

    private func loadHapticPattern() {
        let safeEvents = events.filter { event in
            event.time + max(0, event.duration) < videoDuration - stopBeforeEnd
        }
        hapticPatternLoaded = hapticService.loadPattern(safeEvents)
    }

    private func startHapticPlayback() {
        if !hapticPatternLoaded { loadHapticPattern() }
        guard hapticPatternLoaded else { return }
        hapticService.seekAdvancedPlayer(to: currentTime)
        hapticService.startAdvancedPlayer()
    }

    /// Rebuilds the loaded CHHapticPattern after edits. Debounced so rapid
    /// slider drags don't thrash the engine.
    func reloadHapticPattern(resumeIfPlaying: Bool = true) {
        let now = Date()
        guard now.timeIntervalSince(lastReloadStamp) >= reloadDebounce else { return }
        lastReloadStamp = now

        let wasPlaying = isPlaying
        hapticService.stopAdvancedPlayer()
        hapticPatternLoaded = false
        loadHapticPattern()
        if wasPlaying && resumeIfPlaying {
            hapticService.seekAdvancedPlayer(to: currentTime)
            hapticService.startAdvancedPlayer()
        }
    }

    // MARK: - Playback Control

    func togglePlayPause() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
        } else {
            // If we're at the end, rewind first
            if currentTime >= videoDuration - stopBeforeEnd {
                seek(to: 0)
            }
            if !hapticPatternLoaded { loadHapticPattern() }
            player.play()
        }
    }

    func skipBackward(by seconds: Double = 5.0) {
        seek(to: max(0, currentTime - seconds))
    }

    func skipForward(by seconds: Double = 5.0) {
        seek(to: min(videoDuration - stopBeforeEnd, currentTime + seconds))
    }

    func seek(to time: Double) {
        let clamped = max(0, min(videoDuration, time))
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
        if hapticPatternLoaded {
            hapticService.seekAdvancedPlayer(to: clamped)
            if isPlaying { hapticService.startAdvancedPlayer() }
        }
    }

    private func handleVideoEnd() {
        isPlaying = false
        hapticService.forceStopAllHaptics()
        hapticPatternLoaded = false
        // Snap playhead to the safe boundary
        currentTime = max(0, videoDuration - stopBeforeEnd)
    }

    // MARK: - Event Editing

    /// Insert and sort, then reload pattern.
    func addEvent(_ event: HapticEvent) {
        // Don't allow events past the safe boundary
        guard event.time < videoDuration - stopBeforeEnd else { return }
        events.append(event)
        events.sort { $0.time < $1.time }
        reloadHapticPattern()
    }

    func updateEvent(id: UUID, intensity: Float? = nil, sharpness: Float? = nil, duration: Double? = nil, time: Double? = nil) {
        guard let idx = events.firstIndex(where: { $0.id == id }) else { return }
        var ev = events[idx]
        if let intensity { ev.intensity = max(0, min(1, intensity)) }
        if let sharpness { ev.sharpness = max(0, min(1, sharpness)) }
        if let duration  { ev.duration = max(0, min(videoDuration - ev.time - stopBeforeEnd, duration)) }
        if let time {
            ev.time = max(0, min(videoDuration - stopBeforeEnd - 0.01, time))
        }
        events[idx] = ev
        events.sort { $0.time < $1.time }
        reloadHapticPattern()
    }

    func deleteEvent(id: UUID) {
        events.removeAll { $0.id == id }
        reloadHapticPattern()
    }

    func clearAllEvents() {
        events.removeAll()
        reloadHapticPattern()
    }

    /// Plays a single event in isolation for the inspector preview button.
    func previewEvent(_ event: HapticEvent) {
        var testEvent = event
        testEvent.duration = min(testEvent.duration, 0.3)
        hapticService.resetPlayedEvents()
        hapticService.playEvent(testEvent)
    }

    // MARK: - Cleanup

    func cleanup() {
        hapticService.forceStopAllHaptics()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        rateObserver?.invalidate()
        rateObserver = nil
        if let endObserver = endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player?.pause()
        player = nil
        hapticPatternLoaded = false
    }
}
