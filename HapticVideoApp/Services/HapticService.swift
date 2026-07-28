//
//  HapticService.swift
//  HapticVideoApp
//
//  Rewritten to use CHHapticAdvancedPatternPlayer for proper video sync
//

import Foundation
import CoreHaptics
import AVFAudio

class HapticService {
    static let shared = HapticService()
    
    private var engine: CHHapticEngine?
    private var advancedPlayer: CHHapticAdvancedPatternPlayer?
    /// Separate player for the waveform-following envelope bed. Parameter
    /// curves modulate EVERY event on their player, so the bed must be
    /// isolated or its envelope would scale down accent hits on top.
    private var bedPlayer: CHHapticAdvancedPatternPlayer?
    private var activePlayers: [CHHapticPatternPlayer] = []
    private var playedEventIDs: Set<UUID> = []
    private var isEngineRunning: Bool = false
    /// Last events handed to loadPattern — replayed to rebuild the advanced
    /// player after an engine reset (interruption, backgrounding).
    private var lastLoadedEvents: [HapticEvent] = []
    /// Set when the engine stopped/reset while players existed; the next
    /// ensureEngineRunning() rebuilds them so haptics self-heal.
    private var playersNeedRebuild = false
    
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
            // Shared audio session: AVPlayer activating the session for video
            // no longer interrupts a standalone engine (which caused haptic
            // dead zones at the start of every video). Haptics-only skips
            // audio resource reservation entirely.
            engine = try CHHapticEngine(audioSession: .sharedInstance())
            engine?.playsHapticsOnly = true

            // Both reset (media-server crash) and stop (backgrounding, call,
            // Siri, route change) leave any created players bound to a dead
            // engine session. Recovery is the same: restart on demand and
            // rebuild players from the last loaded events.
            engine?.resetHandler = { [weak self] in
                print("🔄 Haptic engine reset")
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.advancedPlayer = nil
                    self.bedPlayer = nil
                    self.isEngineRunning = false
                    self.playersNeedRebuild = !self.lastLoadedEvents.isEmpty
                    self.restartEngine()
                }
            }

            engine?.stoppedHandler = { [weak self] reason in
                print("⏹️ Haptic engine stopped: \(reason)")
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isEngineRunning = false
                    self.playersNeedRebuild = self.advancedPlayer != nil || self.bedPlayer != nil
                }
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
        if !isEngineRunning { restartEngine() }
        // Flag cleared BEFORE loadPattern — it calls back into here.
        if playersNeedRebuild, !lastLoadedEvents.isEmpty {
            playersNeedRebuild = false
            _ = loadPattern(lastLoadedEvents)
        }
    }
    
    // MARK: - Preload Pattern for Video Sync
    
    /// User-set playback strength (Profile slider, 0.5–1.5; 0 = unset → 1.0).
    private var userStrength: Float {
        let v = UserDefaults.standard.double(forKey: "hapticStrength")
        return v == 0 ? 1.0 : Float(v)
    }

    /// Preload a complete haptic pattern for synchronized playback
    func loadPattern(_ rawEvents: [HapticEvent]) -> Bool {
        guard let engine = engine else { return false }
        ensureEngineRunning()
        // Apply the global strength setting to playback (UI haptics scale
        // separately inside UIHaptics). Store the UNSCALED events so a
        // strength change between loads isn't compounded.
        lastLoadedEvents = rawEvents
        let strength = userStrength
        let events = strength == 1.0 ? rawEvents : rawEvents.map { e in
            var scaled = e
            scaled.intensity = min(1.0, e.intensity * strength)
            return scaled
        }

        // Stop any existing pattern
        stopAdvancedPlayer()

        // Split: curved continuous events → isolated bed player;
        // everything else → accent player.
        let bedEvents = events.filter(Self.isBedEvent)
        let accentEvents = events.filter { !Self.isBedEvent($0) }

        var accentChEvents: [CHHapticEvent] = []
        for event in accentEvents {
            do {
                accentChEvents.append(try event.toCHHapticEvent())
            } catch {
                print("⚠️ Failed to convert event: \(error)")
            }
        }

        guard !accentChEvents.isEmpty || !bedEvents.isEmpty else {
            print("⚠️ No valid haptic events to load")
            return false
        }

        do {
            if !accentChEvents.isEmpty {
                let pattern = try CHHapticPattern(events: accentChEvents, parameters: [])
                advancedPlayer = try engine.makeAdvancedPlayer(with: pattern)
                advancedPlayer?.completionHandler = { [weak self] error in
                    if let error = error {
                        print("❌ Pattern playback error: \(error)")
                    }
                    self?.isPlaying = false
                }
            }

            bedPlayer = try makeBedPlayer(engine: engine, events: bedEvents)

            print("✅ Loaded pattern: \(accentChEvents.count) accents, \(bedEvents.count) envelope regions")
            return true

        } catch {
            print("❌ Failed to create advanced player: \(error)")
            advancedPlayer = nil
            bedPlayer = nil
            return false
        }
    }

    private static func isBedEvent(_ event: HapticEvent) -> Bool {
        event.type == .continuous && !(event.intensityCurve?.isEmpty ?? true)
    }

    /// Bed events → pattern (events + chained intensity curves) → player.
    /// Shared by loadPattern and the mid-region seek rebuild.
    private func makeBedPlayer(engine: CHHapticEngine, events: [HapticEvent]) throws -> CHHapticAdvancedPatternPlayer? {
        guard !events.isEmpty else { return nil }
        let chEvents = try events.map { try $0.toCHHapticEvent() }
        let curves = Self.parameterCurves(for: events)
        let pattern = try CHHapticPattern(events: chEvents, parameterCurves: curves)
        return try engine.makeAdvancedPlayer(with: pattern)
    }

    /// Slices an envelope at `offset` (relative to event start): points after
    /// the cut are kept with times re-based to the cut, and an interpolated
    /// first point is inserted at time 0.
    private static func sliceCurve(_ points: [HapticCurvePoint], from offset: Double) -> [HapticCurvePoint] {
        let tail = points.filter { $0.time > offset }
        let before = points.last { $0.time <= offset }
        let startValue: Float
        if let before, let after = tail.first, after.time > before.time {
            let t = Float((offset - before.time) / (after.time - before.time))
            startValue = before.value + t * (after.value - before.value)
        } else {
            startValue = before?.value ?? tail.first?.value ?? 0
        }
        return [HapticCurvePoint(time: 0, value: startValue)]
            + tail.map { HapticCurvePoint(time: $0.time - offset, value: $0.value) }
    }

    /// Builds pattern-level intensity + sharpness curves from events'
    /// envelope points. CoreHaptics caps a curve at 16 control points, so
    /// long envelopes are chained as sequential curves.
    private static func parameterCurves(for events: [HapticEvent]) -> [CHHapticParameterCurve] {
        var curves: [CHHapticParameterCurve] = []
        for event in events {
            guard event.type == .continuous else { continue }

            if let curve = event.intensityCurve, curve.count >= 2 {
                let gain = event.intensity
                appendChained(curve, into: &curves, parameterID: .hapticIntensityControl,
                              eventTime: event.time) { min(1, max(0, $0 * gain)) }
            }

            // hapticSharpnessControl is ADDITIVE onto the event's sharpness —
            // the authored curve stores absolute targets, so emit deltas.
            if let curve = event.sharpnessCurve, curve.count >= 2 {
                let base = event.sharpness
                appendChained(curve, into: &curves, parameterID: .hapticSharpnessControl,
                              eventTime: event.time) { min(1, max(-1, $0 - base)) }
            }
        }
        return curves
    }

    private static func appendChained(_ curve: [HapticCurvePoint],
                                      into curves: inout [CHHapticParameterCurve],
                                      parameterID: CHHapticDynamicParameter.ID,
                                      eventTime: Double,
                                      transform: (Float) -> Float) {
        var idx = 0
        while idx < curve.count {
            let slice = Array(curve[idx..<min(idx + 16, curve.count)])
            guard let base = slice.first?.time else { break }
            let points = slice.map {
                CHHapticParameterCurve.ControlPoint(relativeTime: $0.time - base,
                                                    value: transform($0.value))
            }
            curves.append(CHHapticParameterCurve(parameterID: parameterID,
                                                 controlPoints: points,
                                                 relativeTime: eventTime + base))
            idx += 16
        }
    }
    
    // MARK: - Advanced Player Control (for video sync)
    
    /// Whether a pattern is currently loaded into players (they die on
    /// engine stop or another screen's cleanup — callers reload if false).
    var isPatternLoaded: Bool {
        advancedPlayer != nil || bedPlayer != nil
    }

    func startAdvancedPlayer() {
        guard advancedPlayer != nil || bedPlayer != nil else { return }
        ensureEngineRunning()

        do {
            try advancedPlayer?.start(atTime: CHHapticTimeImmediate)
            try bedPlayer?.start(atTime: CHHapticTimeImmediate)
            isPlaying = true
            print("▶️ Advanced player started")
        } catch {
            print("❌ Failed to start advanced player: \(error)")
        }
    }

    func pauseAdvancedPlayer() {
        do {
            try advancedPlayer?.pause(atTime: CHHapticTimeImmediate)
            try bedPlayer?.pause(atTime: CHHapticTimeImmediate)
            isPlaying = false
            print("⏸️ Advanced player paused")
        } catch {
            print("❌ Failed to pause advanced player: \(error)")
        }
    }

    func seekAdvancedPlayer(to time: Double) {
        let rebuiltBed = rebuildBedIfStraddling(at: time)
        do {
            try advancedPlayer?.seek(toOffset: time)
            try bedPlayer?.seek(toOffset: time)
            // A rebuilt player starts stopped — resume it if we were playing.
            if rebuiltBed && isPlaying {
                try bedPlayer?.start(atTime: CHHapticTimeImmediate)
            }
            print("⏩ Seeked to \(String(format: "%.2f", time))s")
        } catch {
            print("❌ Failed to seek advanced player: \(error)")
        }
    }

    /// Seeking skips events whose start precedes the offset, so landing in
    /// the middle of a long envelope region left the bed silent (and stale
    /// curves behind). Rebuild the bed with the straddling event clipped to
    /// start at the seek time — times stay on the original absolute timeline
    /// so the shared seek offset still lines up. Returns true if rebuilt;
    /// any failure falls back to the plain seek on the existing player.
    private func rebuildBedIfStraddling(at time: Double) -> Bool {
        guard let engine, bedPlayer != nil else { return false }
        let bedEvents = lastLoadedEvents.filter(Self.isBedEvent)
        guard bedEvents.contains(where: { $0.time < time && time < $0.time + $0.duration }) else { return false }

        var clipped: [HapticEvent] = []
        for var event in bedEvents {
            if event.time + event.duration <= time { continue }   // entirely before: drop
            if event.time < time {                                // straddler: clip
                let offset = time - event.time
                if let curve = event.intensityCurve {
                    var sliced = Self.sliceCurve(curve, from: offset)
                    if sliced.count < 2 {
                        // Envelope ended before the cut — hold its last value.
                        let v = sliced.first?.value ?? event.intensity
                        sliced = [HapticCurvePoint(time: 0, value: v),
                                  HapticCurvePoint(time: event.duration - offset, value: v)]
                    }
                    event.intensityCurve = sliced
                }
                event.time = time
                event.duration -= offset
            }
            clipped.append(event)
        }

        do {
            try bedPlayer?.stop(atTime: CHHapticTimeImmediate)
            bedPlayer = try makeBedPlayer(engine: engine, events: clipped)
            return true
        } catch {
            print("⚠️ Bed rebuild for seek failed, plain seek fallback: \(error)")
            return false
        }
    }

    func stopAdvancedPlayer() {
        do {
            try advancedPlayer?.stop(atTime: CHHapticTimeImmediate)
            try bedPlayer?.stop(atTime: CHHapticTimeImmediate)
            isPlaying = false
        } catch {
            print("❌ Failed to stop advanced player: \(error)")
        }

        advancedPlayer = nil
        bedPlayer = nil
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
            // Play NOW: zero out the event's absolute video timestamp.
            // (Passing it through as relativeTime delayed feed-playback
            // haptics by the event's position in the video.)
            var immediate = event
            immediate.time = 0
            immediate.intensity = min(1.0, immediate.intensity * userStrength)
            let hapticEvent = try immediate.toCHHapticEvent()
            let pattern: CHHapticPattern
            if immediate.type == .continuous, immediate.intensityCurve?.isEmpty == false {
                let curves = Self.parameterCurves(for: [immediate])
                pattern = try CHHapticPattern(events: [hapticEvent], parameterCurves: curves)
            } else {
                pattern = try CHHapticPattern(events: [hapticEvent], parameters: [])
            }
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
    
    /// Stops every player. Alias kept for call sites; stopping the players is
    /// sufficient — the old engine stop/restart cycle raced with quick
    /// pause/resume and intermittently killed haptics.
    func forceStopAllHaptics() {
        stopAllHaptics()
    }

    func resetPlayedEvents() {
        playedEventIDs.removeAll()
    }
}
