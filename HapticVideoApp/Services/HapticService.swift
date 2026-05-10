//
//  HapticService.swift
//  HapticVideoApp
//
//  Rewritten to use CHHapticAdvancedPatternPlayer for proper video sync
//

import Foundation
import CoreHaptics

class HapticService {
    static let shared = HapticService()
    
    private var engine: CHHapticEngine?
    private var advancedPlayer: CHHapticAdvancedPatternPlayer?
    private var activePlayers: [CHHapticPatternPlayer] = []
    private var playedEventIDs: Set<UUID> = []
    private var isEngineRunning: Bool = false
    
    var isPlaying: Bool = false
    
    private init() {
        setupEngine()
    }
    
    // MARK: - Engine Setup
    
    private func setupEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            print("⚠️ Device doesn't support haptics")
            return
        }
        
        do {
            engine = try CHHapticEngine()
            
            engine?.resetHandler = { [weak self] in
                print("🔄 Haptic engine reset")
                self?.restartEngine()
            }
            
            engine?.stoppedHandler = { [weak self] reason in
                print("⏹️ Haptic engine stopped: \(reason)")
                self?.isEngineRunning = false
            }
            
            try engine?.start()
            isEngineRunning = true
            print("✅ Haptic engine started")
            
        } catch {
            print("❌ Haptic engine error: \(error)")
        }
    }
    
    private func restartEngine() {
        do {
            try engine?.start()
            isEngineRunning = true
        } catch {
            print("❌ Failed to restart engine: \(error)")
        }
    }
    
    private func ensureEngineRunning() {
        guard !isEngineRunning else { return }
        restartEngine()
    }
    
    // MARK: - Preload Pattern for Video Sync
    
    /// Preload a complete haptic pattern for synchronized playback
    func loadPattern(_ events: [HapticEvent]) -> Bool {
        guard let engine = engine else { return false }
        ensureEngineRunning()
        
        // Stop any existing pattern
        stopAdvancedPlayer()
        
        // Convert events to CHHapticEvents
        var chEvents: [CHHapticEvent] = []
        for event in events {
            do {
                let chEvent = try event.toCHHapticEvent()
                chEvents.append(chEvent)
            } catch {
                print("⚠️ Failed to convert event: \(error)")
            }
        }
        
        guard !chEvents.isEmpty else {
            print("⚠️ No valid haptic events to load")
            return false
        }
        
        do {
            let pattern = try CHHapticPattern(events: chEvents, parameters: [])
            advancedPlayer = try engine.makeAdvancedPlayer(with: pattern)
            
            advancedPlayer?.completionHandler = { [weak self] error in
                if let error = error {
                    print("❌ Pattern playback error: \(error)")
                }
                self?.isPlaying = false
            }
            
            print("✅ Loaded pattern with \(chEvents.count) events")
            return true
            
        } catch {
            print("❌ Failed to create advanced player: \(error)")
            return false
        }
    }
    
    // MARK: - Advanced Player Control (for video sync)
    
    func startAdvancedPlayer() {
        guard let player = advancedPlayer else { return }
        ensureEngineRunning()
        
        do {
            try player.start(atTime: CHHapticTimeImmediate)
            isPlaying = true
            print("▶️ Advanced player started")
        } catch {
            print("❌ Failed to start advanced player: \(error)")
        }
    }
    
    func pauseAdvancedPlayer() {
        guard let player = advancedPlayer else { return }
        
        do {
            try player.pause(atTime: CHHapticTimeImmediate)
            isPlaying = false
            print("⏸️ Advanced player paused")
        } catch {
            print("❌ Failed to pause advanced player: \(error)")
        }
    }
    
    func resumeAdvancedPlayer() {
        guard let player = advancedPlayer else { return }
        ensureEngineRunning()
        
        do {
            try player.resume(atTime: CHHapticTimeImmediate)
            isPlaying = true
            print("▶️ Advanced player resumed")
        } catch {
            print("❌ Failed to resume advanced player: \(error)")
        }
    }
    
    func seekAdvancedPlayer(to time: Double) {
        guard let player = advancedPlayer else { return }
        
        do {
            try player.seek(toOffset: time)
            print("⏩ Seeked to \(String(format: "%.2f", time))s")
        } catch {
            print("❌ Failed to seek advanced player: \(error)")
        }
    }
    
    func stopAdvancedPlayer() {
        guard let player = advancedPlayer else { return }
        
        do {
            try player.stop(atTime: CHHapticTimeImmediate)
            isPlaying = false
            print("⏹️ Advanced player stopped")
        } catch {
            print("❌ Failed to stop advanced player: \(error)")
        }
        
        advancedPlayer = nil
    }
    
    // MARK: - Play Single Event (fallback for editor preview)
    
    func playEvent(_ event: HapticEvent) {
        guard let engine = engine else { return }
        ensureEngineRunning()
        
        if playedEventIDs.contains(event.id) {
            return
        }
        playedEventIDs.insert(event.id)
        
        if playedEventIDs.count > 100 {
            playedEventIDs.removeAll()
        }
        
        do {
            let hapticEvent = try event.toCHHapticEvent()
            let pattern = try CHHapticPattern(events: [hapticEvent], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            
            // Track continuous players
            if event.type == .continuous && event.duration > 0 {
                activePlayers.append(player)
                
                // Auto-remove after duration
                DispatchQueue.main.asyncAfter(deadline: .now() + event.duration + 0.1) { [weak self] in
                    self?.activePlayers.removeAll { $0 === player }
                }
            }
            
            try player.start(atTime: 0)
            
        } catch {
            print("❌ Haptic play error: \(error)")
        }
    }
    
    // MARK: - Stop All Haptics IMMEDIATELY
    
    func stopAllHaptics() {
        // Stop advanced player first
        stopAdvancedPlayer()
        
        // Stop ALL individual players immediately
        for player in activePlayers {
            do {
                try player.stop(atTime: CHHapticTimeImmediate)
            } catch {
                // Ignore errors - player may already be stopped
            }
        }
        
        activePlayers.removeAll()
        playedEventIDs.removeAll()
        isPlaying = false
        
        print("🛑 All haptics stopped immediately")
    }
    
    /// Force stop by restarting the engine - guaranteed to stop everything
    func forceStopAllHaptics() {
        stopAllHaptics()
        
        // Nuclear option: restart engine to guarantee all haptics stop
        engine?.stop(completionHandler: { [weak self] error in
            if let error = error {
                print("⚠️ Engine stop error: \(error)")
            }
            self?.isEngineRunning = false
            
            // Restart for next use
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.restartEngine()
            }
        })
        
        print("🔴 Force stopped all haptics (engine restart)")
    }
    
    // MARK: - Legacy Control Methods
    
    func seekHaptics(to time: Double) {
        stopAllHaptics()
        print("🔍 Seeked to \(time)s")
    }
    
    func resumeHaptics() {
        isPlaying = true
        print("▶️ Haptics resumed")
    }
    
    func pauseHaptics() {
        stopAllHaptics()
        isPlaying = false
        print("⏸️ Haptics paused")
    }
    
    func resetPlayedEvents() {
        playedEventIDs.removeAll()
    }
}
