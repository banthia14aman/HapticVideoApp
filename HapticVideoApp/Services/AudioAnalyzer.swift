//
//  AudioAnalyzer.swift
//  HapticVideoApp
//
//  Advanced audio analysis using FFT spectral analysis, multi-band decomposition,
//  spectral flux onset detection, and perceptual weighting for haptic generation.
//

import Foundation
import Accelerate
import AVFoundation

// MARK: - Audio Analysis Result

struct AudioAnalysisFrame {
    let time: Double
    let rms: Float
    let spectralFlux: Float
    let bandEnergies: [Float]  // Sub-bass, Bass, Low-mid, Mid, High
    let spectralCentroid: Float
    let isOnset: Bool
    let onsetStrength: Float
}

// MARK: - Frequency Band

enum FrequencyBand: Int, CaseIterable {
    case subBass = 0    // 20-60 Hz - Rumble, explosions
    case bass = 1       // 60-250 Hz - Kicks, punches
    case lowMid = 2     // 250-500 Hz - Dialogue, ambient
    case mid = 3        // 500-2000 Hz - Snares, clicks
    case high = 4       // 2000-20000 Hz - Hi-hats, glass
    
    var frequencyRange: (min: Float, max: Float) {
        switch self {
        case .subBass: return (20, 60)
        case .bass: return (60, 250)
        case .lowMid: return (250, 500)
        case .mid: return (500, 2000)
        case .high: return (2000, 20000)
        }
    }
    
    var hapticType: HapticEventType {
        switch self {
        case .subBass: return .continuous
        case .bass: return .impact
        case .lowMid: return .continuous
        case .mid: return .transient
        case .high: return .transient
        }
    }
    
    var intensityMultiplier: Float {
        switch self {
        case .subBass: return 1.2  // Boost sub-bass feel
        case .bass: return 1.0
        case .lowMid: return 0.6  // Softer for dialogue
        case .mid: return 0.9
        case .high: return 0.7
        }
    }
    
    var sharpnessValue: Float {
        switch self {
        case .subBass: return 0.2
        case .bass: return 0.4
        case .lowMid: return 0.3
        case .mid: return 0.7
        case .high: return 0.9
        }
    }
}

// MARK: - Audio Analyzer

class AudioAnalyzer {
    
    // MARK: - FFT Configuration
    
    private let fftSize: Int = 2048
    private let hopSize: Int = 512
    private let sampleRate: Float = 44100.0
    
    // FFT setup
    private var fftSetup: FFTSetup?
    private var log2n: vDSP_Length
    
    // Buffers
    private var window: [Float]
    private var realBuffer: [Float]
    private var imagBuffer: [Float]
    private var magnitudeBuffer: [Float]
    private var previousMagnitude: [Float]
    
    // Adaptive threshold state
    private var onsetHistory: [Float] = []
    private let onsetHistorySize = 50
    
    init() {
        log2n = vDSP_Length(log2(Float(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        
        // Hann window for better frequency resolution
        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        
        realBuffer = [Float](repeating: 0, count: fftSize / 2)
        imagBuffer = [Float](repeating: 0, count: fftSize / 2)
        magnitudeBuffer = [Float](repeating: 0, count: fftSize / 2)
        previousMagnitude = [Float](repeating: 0, count: fftSize / 2)
    }
    
    deinit {
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }
    
    // MARK: - Main Analysis
    
    func analyzeAudio(samples: [Float], videoDuration: Double, progressCallback: ((Double) -> Void)?) -> [AudioAnalysisFrame] {
        var frames: [AudioAnalysisFrame] = []
        let totalFrames = (samples.count - fftSize) / hopSize
        
        var frameIndex = 0
        var sampleIndex = 0
        
        while sampleIndex + fftSize <= samples.count {
            let currentTime = Double(sampleIndex) / Double(sampleRate)
            
            // Stop before video end
            if currentTime >= videoDuration - 1.0 {
                break
            }
            
            // Extract frame
            let frame = Array(samples[sampleIndex..<sampleIndex + fftSize])
            let analysis = analyzeFrame(frame, time: currentTime)
            frames.append(analysis)
            
            sampleIndex += hopSize
            frameIndex += 1
            
            // Progress callback
            if frameIndex % 100 == 0 {
                progressCallback?(Double(frameIndex) / Double(totalFrames))
            }
        }
        
        // Post-process: detect onsets with adaptive threshold
        return detectOnsets(in: frames)
    }
    
    // MARK: - Frame Analysis
    
    private func analyzeFrame(_ samples: [Float], time: Double) -> AudioAnalysisFrame {
        // Apply window
        var windowedSamples = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(samples, 1, window, 1, &windowedSamples, 1, vDSP_Length(fftSize))
        
        // Perform FFT
        performFFT(windowedSamples)
        
        // Calculate features
        let rms = calculateRMS(samples)
        let bandEnergies = calculateBandEnergies()
        let spectralFlux = calculateSpectralFlux()
        let centroid = calculateSpectralCentroid()
        
        // Save magnitude for next frame
        previousMagnitude = magnitudeBuffer
        
        return AudioAnalysisFrame(
            time: time,
            rms: rms,
            spectralFlux: spectralFlux,
            bandEnergies: bandEnergies,
            spectralCentroid: centroid,
            isOnset: false,  // Will be determined in post-processing
            onsetStrength: spectralFlux
        )
    }
    
    // MARK: - FFT
    
    private func performFFT(_ samples: [Float]) {
        guard let setup = fftSetup else { return }
        
        var complexBuffer = DSPSplitComplex(realp: &realBuffer, imagp: &imagBuffer)
        
        samples.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                vDSP_ctoz(complexPtr, 2, &complexBuffer, 1, vDSP_Length(fftSize / 2))
            }
        }
        
        vDSP_fft_zrip(setup, &complexBuffer, 1, log2n, FFTDirection(FFT_FORWARD))
        
        // Calculate magnitude
        vDSP_zvmags(&complexBuffer, 1, &magnitudeBuffer, 1, vDSP_Length(fftSize / 2))
        
        // Convert to dB scale
        var one: Float = 1.0
        vDSP_vdbcon(magnitudeBuffer, 1, &one, &magnitudeBuffer, 1, vDSP_Length(fftSize / 2), 0)
    }
    
    // MARK: - Feature Extraction
    
    private func calculateRMS(_ samples: [Float]) -> Float {
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return rms
    }
    
    private func calculateBandEnergies() -> [Float] {
        var energies: [Float] = []
        
        for band in FrequencyBand.allCases {
            let range = band.frequencyRange
            let minBin = Int(range.min * Float(fftSize) / sampleRate)
            let maxBin = min(Int(range.max * Float(fftSize) / sampleRate), fftSize / 2 - 1)
            
            guard maxBin > minBin else {
                energies.append(0)
                continue
            }
            
            var energy: Float = 0
            let binCount = maxBin - minBin
            
            for bin in minBin..<maxBin {
                energy += magnitudeBuffer[bin]
            }
            
            // Normalize and apply perceptual weighting
            energy = energy / Float(binCount)
            energy = applyPerceptualWeighting(energy, for: band)
            
            energies.append(max(0, energy + 96) / 96)  // Normalize from dB
        }
        
        return energies
    }
    
    private func applyPerceptualWeighting(_ energy: Float, for band: FrequencyBand) -> Float {
        // A-weighting approximation for different bands
        let weights: [FrequencyBand: Float] = [
            .subBass: 0.3,   // Heavy attenuation at low frequencies
            .bass: 0.7,
            .lowMid: 0.9,
            .mid: 1.0,       // Reference (1-4kHz most sensitive)
            .high: 0.85
        ]
        return energy * (weights[band] ?? 1.0)
    }
    
    private func calculateSpectralFlux() -> Float {
        var flux: Float = 0
        
        for i in 0..<magnitudeBuffer.count {
            // Only count increases (half-wave rectification)
            let diff = magnitudeBuffer[i] - previousMagnitude[i]
            if diff > 0 {
                flux += diff * diff
            }
        }
        
        return sqrt(flux)
    }
    
    private func calculateSpectralCentroid() -> Float {
        var weightedSum: Float = 0
        var totalMagnitude: Float = 0
        
        for i in 0..<magnitudeBuffer.count {
            let frequency = Float(i) * sampleRate / Float(fftSize)
            let magnitude = magnitudeBuffer[i] > 0 ? pow(10, magnitudeBuffer[i] / 20) : 0
            weightedSum += frequency * magnitude
            totalMagnitude += magnitude
        }
        
        guard totalMagnitude > 0 else { return 0 }
        return weightedSum / totalMagnitude / (sampleRate / 2)  // Normalize to 0-1
    }
    
    // MARK: - Onset Detection
    
    private func detectOnsets(in frames: [AudioAnalysisFrame]) -> [AudioAnalysisFrame] {
        guard frames.count > 2 else { return frames }
        
        var processedFrames = frames
        
        // Calculate adaptive threshold
        let fluxValues = frames.map { $0.spectralFlux }
        let meanFlux = fluxValues.reduce(0, +) / Float(fluxValues.count)
        let stdFlux = sqrt(fluxValues.map { pow($0 - meanFlux, 2) }.reduce(0, +) / Float(fluxValues.count))
        
        let threshold = meanFlux + 1.5 * stdFlux
        
        // Detect onsets using peak picking
        for i in 1..<frames.count - 1 {
            let current = frames[i].spectralFlux
            let previous = frames[i - 1].spectralFlux
            let next = frames[i + 1].spectralFlux
            
            // Local maximum above threshold
            let isLocalMax = current > previous && current > next
            let aboveThreshold = current > threshold
            
            if isLocalMax && aboveThreshold {
                processedFrames[i] = AudioAnalysisFrame(
                    time: frames[i].time,
                    rms: frames[i].rms,
                    spectralFlux: frames[i].spectralFlux,
                    bandEnergies: frames[i].bandEnergies,
                    spectralCentroid: frames[i].spectralCentroid,
                    isOnset: true,
                    onsetStrength: (current - threshold) / stdFlux
                )
            }
        }
        
        return processedFrames
    }
    
    // MARK: - Haptic Event Generation (Responsive & Satisfying)

    func generateHapticEvents(from frames: [AudioAnalysisFrame],
                              videoDuration: Double,
                              aiContext: AIVideoContext = .empty) -> [HapticEvent] {
        var events: [HapticEvent] = []
        var lastEventTime: Double = -10

        // MORE RESPONSIVE: 100ms cooldown
        let globalMinInterval: Double = 0.10

        // ALL onset frames matter
        let onsetFrames = frames.filter { $0.isOnset }

        // Also include high-energy frames
        let highEnergyFrames = frames.filter { !$0.isOnset && $0.rms > 0.25 }

        // Combine all significant frames
        var significantFrames = onsetFrames

        // Add top 30% of high energy frames
        if !highEnergyFrames.isEmpty {
            let sortedEnergy = highEnergyFrames.sorted { $0.rms > $1.rms }
            let topEnergy = Array(sortedEnergy.prefix(max(10, highEnergyFrames.count / 3)))
            significantFrames.append(contentsOf: topEnergy)
        }

        significantFrames.sort { $0.time < $1.time }

        // Counters for AI-gate debug logging
        var dialogueSuppressed = 0
        var impactUpgraded = 0

        if significantFrames.isEmpty {
            events = generateFromAllEnergy(frames: frames, videoDuration: videoDuration)
        } else {
            for frame in significantFrames {
                guard frame.time < videoDuration - 1.0 else { continue }
                guard frame.time - lastEventTime >= globalMinInterval else { continue }

                // ─── Phase-1 AI gate ─────────────────────────────────────
                // Check impact class first — an explosion in a dialogue
                // scene should still trigger a haptic.
                let impactUpgrade = aiContext.matchingImpactClass(at: frame.time,
                                                                  minConfidence: 0.5)

                // Suppress for dialogue only if no high-priority impact is
                // happening at the same time.
                if impactUpgrade == nil
                    && aiContext.isLabelActive(matching: "speech",
                                               at: frame.time,
                                               minConfidence: 0.7) {
                    dialogueSuppressed += 1
                    continue
                }
                // ─────────────────────────────────────────────────────────

                let (dominantBand, dominantEnergy) = findDominantBand(frame.bandEnergies)

                // Very low threshold - respond to most audio
                guard dominantEnergy > 0.15 || frame.isOnset else { continue }

                var eventType = selectResponsiveEventType(
                    band: dominantBand,
                    isOnset: frame.isOnset,
                    onsetStrength: frame.onsetStrength,
                    energy: dominantEnergy
                )

                var intensity = calculateResponsiveIntensity(
                    frame: frame,
                    band: dominantBand,
                    isOnset: frame.isOnset
                )

                let sharpness = calculateSharpness(frame: frame, band: dominantBand)
                let duration = calculateResponsiveDuration(for: eventType, energy: dominantEnergy)

                // ─── Phase-1 AI gate: impact upgrade ──────────────────────
                if let upgrade = impactUpgrade {
                    eventType = upgrade.preferredType
                    intensity = min(1.0, intensity * upgrade.intensityBoost)
                    impactUpgraded += 1
                }
                // ─────────────────────────────────────────────────────────

                let event = HapticEvent(
                    time: frame.time,
                    intensity: intensity,
                    sharpness: sharpness,
                    duration: duration,
                    type: eventType
                )

                events.append(event)
                lastEventTime = frame.time
            }
        }

        // ─── Phase-1 second pass: visual-only events ──────────────────────
        let visualEvents = generateVisualOnlyEvents(aiContext: aiContext,
                                                    existingEvents: events,
                                                    videoDuration: videoDuration)
        if !visualEvents.isEmpty {
            events.append(contentsOf: visualEvents)
            events.sort { $0.time < $1.time }
        }
        // ─────────────────────────────────────────────────────────────────

        var finalEvents = deduplicateEvents(events)

        // Allow up to 5 events per second for responsive feel
        let maxEvents = Int(videoDuration * 5)
        if finalEvents.count > maxEvents {
            finalEvents = Array(finalEvents.sorted { $0.intensity > $1.intensity }.prefix(maxEvents))
            finalEvents.sort { $0.time < $1.time }
        }

        print("💪 Generated \(finalEvents.count) haptics for \(String(format: "%.1f", videoDuration))s video"
              + "  [dialogue-suppressed: \(dialogueSuppressed),"
              + " impact-upgraded: \(impactUpgraded),"
              + " visual-only added: \(visualEvents.count)]")
        return finalEvents
    }

    // MARK: - Visual-only events (Phase-1)

    /// Emit `.impact` events for motion spikes that the audio pass missed.
    /// Skips windows where dialogue is active (unless an impact-class is
    /// also detected, in which case the audio loop handles it already).
    private func generateVisualOnlyEvents(aiContext: AIVideoContext,
                                          existingEvents: [HapticEvent],
                                          videoDuration: Double) -> [HapticEvent] {
        guard !aiContext.motionSamples.isEmpty else { return [] }

        let (mean, std) = aiContext.motionStats()
        guard std > 0 else { return [] }
        let threshold = mean + 2 * std

        var visualEvents: [HapticEvent] = []
        var lastVisualTime: Double = -10

        for sample in aiContext.motionSamples {
            guard sample.magnitude > threshold else { continue }
            guard sample.time < videoDuration - 1.0 else { continue }
            guard sample.time - lastVisualTime >= 0.25 else { continue }

            // Skip when there's already an event in this window — the
            // audio pipeline got it.
            let nearby = existingEvents.contains { abs($0.time - sample.time) < 0.1 }
            if nearby { continue }

            // Honour the dialogue gate unless an impact class is firing.
            let impact = aiContext.matchingImpactClass(at: sample.time, minConfidence: 0.5)
            if impact == nil
                && aiContext.isLabelActive(matching: "speech",
                                           at: sample.time,
                                           minConfidence: 0.7) {
                continue
            }

            // Intensity scales with motion z-score, clamped to a satisfying range.
            let z = (sample.magnitude - mean) / max(std, 0.001)
            let intensity: Float = min(1.0, max(0.55, 0.55 + z * 0.12))

            visualEvents.append(HapticEvent(
                time: sample.time,
                intensity: intensity,
                sharpness: 0.5,
                duration: 0,
                type: .impact
            ))
            lastVisualTime = sample.time
        }

        return visualEvents
    }
    
    /// Generate from all energy when no onsets
    private func generateFromAllEnergy(frames: [AudioAnalysisFrame], videoDuration: Double) -> [HapticEvent] {
        var events: [HapticEvent] = []
        var lastEventTime: Double = -10
        
        let sortedFrames = frames.sorted { $0.rms > $1.rms }
        let topCount = max(20, frames.count / 5)  // Top 20%
        let topFrames = Array(sortedFrames.prefix(topCount))
        
        for frame in topFrames.sorted(by: { $0.time < $1.time }) {
            guard frame.time < videoDuration - 1.0 else { continue }
            guard frame.time - lastEventTime >= 0.12 else { continue }
            
            let (dominantBand, dominantEnergy) = findDominantBand(frame.bandEnergies)
            
            let event = HapticEvent(
                time: frame.time,
                intensity: min(1.0, max(0.5, frame.rms * 2.5)),
                sharpness: dominantBand.sharpnessValue,
                duration: dominantBand == .subBass || dominantBand == .bass ? 0.08 : 0,
                type: dominantBand.hapticType
            )
            
            events.append(event)
            lastEventTime = frame.time
        }
        
        return events
    }
    
    /// Select event type - more variety
    private func selectResponsiveEventType(band: FrequencyBand, isOnset: Bool, onsetStrength: Float, energy: Float) -> HapticEventType {
        // Strong onsets = crisp transient
        if isOnset && onsetStrength > 1.0 {
            return .transient
        }
        
        // Bass = satisfying impact or rumble
        if band == .bass {
            return .impact
        }
        
        if band == .subBass {
            return energy > 0.4 ? .continuous : .impact
        }
        
        // Mid/High = transient
        if band == .high || band == .mid {
            return .transient
        }
        
        // Low-mid can be continuous for sustained sounds
        if band == .lowMid && energy > 0.35 {
            return .continuous
        }
        
        return isOnset ? .transient : .impact
    }
    
    /// Calculate intensity - HIGHER base, more dynamic
    private func calculateResponsiveIntensity(frame: AudioAnalysisFrame, band: FrequencyBand, isOnset: Bool) -> Float {
        let baseIntensity = frame.bandEnergies[band.rawValue]
        let rmsInfluence = frame.rms * 0.4
        
        var intensity = (baseIntensity * 0.6 + rmsInfluence + 0.3) * band.intensityMultiplier
        
        // Significant boost for onsets
        if isOnset {
            let onsetBoost = min(0.3, frame.onsetStrength * 0.1)
            intensity += onsetBoost
        }
        
        // HIGHER RANGE: 0.5 to 1.0 for satisfying feel
        return min(1.0, max(0.5, intensity))
    }
    
    /// Duration - allow some sustain
    private func calculateResponsiveDuration(for type: HapticEventType, energy: Float) -> Double {
        switch type {
        case .transient:
            return 0
        case .impact:
            return 0
        case .continuous:
            // Satisfying sustain (0.08 to 0.2 seconds)
            return min(0.2, max(0.08, Double(energy) * 0.25))
        }
    }
    
    private func findDominantBand(_ energies: [Float]) -> (FrequencyBand, Float) {
        var maxEnergy: Float = 0
        var dominantBand: FrequencyBand = .mid
        
        for (index, energy) in energies.enumerated() {
            guard let band = FrequencyBand(rawValue: index) else { continue }
            let weightedEnergy = energy * band.intensityMultiplier
            if weightedEnergy > maxEnergy {
                maxEnergy = weightedEnergy
                dominantBand = band
            }
        }
        
        return (dominantBand, maxEnergy)
    }
    
    private func calculateIntensity(frame: AudioAnalysisFrame, band: FrequencyBand) -> Float {
        let baseIntensity = frame.bandEnergies[band.rawValue]
        let onsetBoost: Float = frame.isOnset ? min(0.3, frame.onsetStrength * 0.1) : 0
        
        return min(1.0, max(0.2, baseIntensity * band.intensityMultiplier + onsetBoost))
    }
    
    private func calculateSharpness(frame: AudioAnalysisFrame, band: FrequencyBand) -> Float {
        // Blend band sharpness with spectral centroid
        let bandSharpness = band.sharpnessValue
        let centroidSharpness = frame.spectralCentroid
        
        return min(1.0, (bandSharpness * 0.7 + centroidSharpness * 0.3))
    }
    
    private func calculateDuration(for type: HapticEventType, energy: Float, availableTime: Double) -> Double {
        switch type {
        case .transient:
            return 0
        case .impact:
            return 0
        case .continuous:
            let baseDuration = Double(energy) * 0.3  // Up to 0.3 seconds
            return min(max(0.05, baseDuration), availableTime - 0.1, 0.3)
        }
    }
    
    private func deduplicateEvents(_ events: [HapticEvent]) -> [HapticEvent] {
        guard events.count > 1 else { return events }
        
        var deduplicated: [HapticEvent] = []
        var lastEventTime: Double = -1
        
        for event in events.sorted(by: { $0.time < $1.time }) {
            // Merge events within 30ms
            if event.time - lastEventTime < 0.03 {
                // Keep the stronger event
                if let lastIndex = deduplicated.indices.last,
                   event.intensity > deduplicated[lastIndex].intensity {
                    deduplicated[lastIndex] = event
                }
            } else {
                deduplicated.append(event)
                lastEventTime = event.time
            }
        }
        
        return deduplicated
    }
}
