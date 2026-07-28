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

        // DSPSplitComplex stores the pointers past the initializer call, so
        // they must come from withUnsafeMutableBufferPointer scopes — the
        // &array shorthand only guarantees call-duration validity.
        realBuffer.withUnsafeMutableBufferPointer { realPtr in
            imagBuffer.withUnsafeMutableBufferPointer { imagPtr in
                var complexBuffer = DSPSplitComplex(realp: realPtr.baseAddress!,
                                                    imagp: imagPtr.baseAddress!)

                samples.withUnsafeBufferPointer { ptr in
                    ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &complexBuffer, 1, vDSP_Length(fftSize / 2))
                    }
                }

                vDSP_fft_zrip(setup, &complexBuffer, 1, log2n, FFTDirection(FFT_FORWARD))

                magnitudeBuffer.withUnsafeMutableBufferPointer { magPtr in
                    vDSP_zvmags(&complexBuffer, 1, magPtr.baseAddress!, 1, vDSP_Length(fftSize / 2))
                }
            }
        }

        // Normalize for FFT gain (unnormalized vDSP FFT scales by N/2, so
        // squared magnitudes carry (N/2)²): full-scale sine → ~-6dB instead
        // of +40dB. Without this, band energies pinned at the 1.0 clamp for
        // any loud content and every accent saturated.
        var normScale: Float = 4.0 / Float(fftSize * fftSize)
        vDSP_vsmul(magnitudeBuffer, 1, &normScale, &magnitudeBuffer, 1, vDSP_Length(fftSize / 2))

        // Floor at 1e-9 BEFORE the dB conversion: log10(0) = -inf, and one
        // -inf bin poisons spectral flux into inf/NaN — which made the
        // adaptive onset threshold unreachable (zero onsets detected, ever).
        var eps: Float = 1e-9
        vDSP_vsadd(magnitudeBuffer, 1, &eps, &magnitudeBuffer, 1, vDSP_Length(fftSize / 2))

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
            
            // Clamp to 0...1 — loud content pushes dB positive, and band
            // energies >1 saturated every accent at intensity 1.0 (which the
            // percentile remap then flattened into uniform mush).
            energies.append(min(1, max(0, energy + 96) / 96))
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

        // Also include high-energy frames (0.35: quiet stretches must stay
        // quiet — constant filler reads as buzz and kills contrast)
        let highEnergyFrames = frames.filter { !$0.isOnset && $0.rms > 0.35 }

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
                                               minConfidence: 0.7)
                    // Singing co-classifies as speech — don't gate music.
                    && !aiContext.isMusicActive(at: frame.time) {
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

                var sharpness = calculateSharpness(frame: frame, band: dominantBand)
                var duration = calculateResponsiveDuration(for: eventType, energy: dominantEnergy)

                // ─── Phase-1 AI gate: impact upgrade ──────────────────────
                if let upgrade = impactUpgrade {
                    eventType = upgrade.preferredType
                    intensity = min(1.0, intensity * upgrade.intensityBoost)
                    if let preferred = upgrade.preferredSharpness {
                        sharpness = preferred
                    }
                    // A class upgrade to .continuous (e.g. engine) needs a
                    // real duration — a 0-duration continuous event is a dud.
                    if eventType == .continuous, duration <= 0 {
                        duration = calculateResponsiveDuration(for: .continuous, energy: dominantEnergy)
                    }
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

        // ─── Awe grading: contrast + hero moment staging (accent layer) ───
        finalEvents = applyAweGrading(to: finalEvents,
                                      frames: frames,
                                      videoDuration: videoDuration,
                                      aiContext: aiContext)

        // ─── Envelope layer: waveform-following continuous haptics ────────
        // The realism layer. Discrete accents ride ON TOP of a continuous
        // rumble whose intensity tracks the audio's low-frequency envelope
        // (same rendering model as Lofelt / Music Haptics).
        var envelopeEvents = generateEnvelopeLayer(frames: frames,
                                                   videoDuration: videoDuration,
                                                   aiContext: aiContext)
        if !envelopeEvents.isEmpty {
            // Envelope replaces discrete continuous blips — keep only
            // transient/impact accents from the symbolic pipeline.
            finalEvents.removeAll { $0.type == .continuous && ($0.intensityCurve?.isEmpty ?? true) }

            // Sidechain duck: one LRA can't render rumble and a click at
            // once — sustained drive physically masks transients. Dip the
            // bed to 25% for ~80ms around every accent so clicks punch
            // through the bass instead of drowning in it.
            let accentTimes = finalEvents
                .filter { $0.type == .transient || $0.type == .impact }
                .map(\.time)
            for i in envelopeEvents.indices {
                guard var curve = envelopeEvents[i].intensityCurve else { continue }
                let start = envelopeEvents[i].time
                for j in curve.indices {
                    let absTime = start + curve[j].time
                    if accentTimes.contains(where: { abs($0 - absTime) < 0.08 }) {
                        curve[j].value *= 0.25
                    }
                }
                envelopeEvents[i].intensityCurve = curve
            }

            finalEvents.append(contentsOf: envelopeEvents)
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
            
            let (dominantBand, _) = findDominantBand(frame.bandEnergies)

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
        let rmsInfluence = frame.rms * 0.35

        // No flat +0.3 offset — with clamped band energies the old formula
        // pushed everything to 1.0, and uniform 1.0 has no dynamics to grade.
        var intensity = (baseIntensity * 0.5 + rmsInfluence + 0.1) * band.intensityMultiplier

        // Significant boost for onsets
        if isOnset {
            let onsetBoost = min(0.35, frame.onsetStrength * 0.12)
            intensity += onsetBoost
        }
        
        // Wide raw range — the awe-grading pass remaps the distribution so
        // soft moments are genuinely soft and peaks genuinely peak.
        // (The old max(0.5,...) floor squashed everything into 0.5–1.0,
        // which is why nothing felt big: there was no contrast left.)
        return min(1.0, max(0.15, intensity))
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
    
    /// Researched Taptic sharpness map: normalized spectral centroid 0 → 0.1
    /// (dullest useful rumble), 1 → 0.95 (glassy click). NOTE: perceived
    /// "punch" peaks around sharpness ≈ 0.73 — beyond that the LRA reads as
    /// thin rather than harder, so don't chase 1.0 for impact feel.
    private func sharpness(forCentroid centroid: Float) -> Float {
        return 0.1 + 0.85 * min(1.0, max(0.0, centroid))
    }

    private func calculateSharpness(frame: AudioAnalysisFrame, band: FrequencyBand) -> Float {
        // Band sharpness acts as a prior, blended 50/50 with the measured
        // centroid via the formal Taptic map.
        return min(1.0, band.sharpnessValue * 0.5 + sharpness(forCentroid: frame.spectralCentroid) * 0.5)
    }
    
    // MARK: - Awe Grading (dynamics, hero moments, rumble bed)

    /// Post-processes the raw event list the way a sound designer mixes a
    /// scene: expand dynamic range, stage the biggest hits with a silence
    /// gap before them and a decaying rumble tail after, and lay a low
    /// bass-following rumble bed under sustained low-frequency energy.
    private func applyAweGrading(to events: [HapticEvent],
                                 frames: [AudioAnalysisFrame],
                                 videoDuration: Double,
                                 aiContext: AIVideoContext) -> [HapticEvent] {
        guard events.count >= 4 else { return events }

        // 1) Dynamic-range expansion: percentile remap so the video's own
        //    quietest events sit near 0.2 and its loudest at 1.0, with a
        //    gamma that keeps mids soft. Contrast is what "big" feels like.
        var graded = events
        let sorted = events.map(\.intensity).sorted()
        let lo = sorted[Int(Float(sorted.count - 1) * 0.15)]
        let hi = sorted[Int(Float(sorted.count - 1) * 0.95)]
        let span = max(hi - lo, 0.05)
        for i in graded.indices {
            let norm = min(1.0, max(0.0, (graded[i].intensity - lo) / span))
            // Perceptual linearization: Core Haptics intensity is ~quadratic
            // (parameter → felt strength), so sqrt at this FINAL mapping makes
            // the graded contrast land as designed (1.0 stays 1.0, mids rise
            // to perceptually linear). Applied once, at output only — the
            // intermediate math above stays in parameter space.
            graded[i].intensity = sqrt(0.2 + 0.8 * pow(norm, 1.4))
        }

        // 2) Hero moments: the single strongest hit in each ~8s window.
        //    Each hero gets: a 0.3s silence gap before it (drop competing
        //    events), full intensity, crisp sharpness, and a decaying
        //    rumble tail after — thud → rumble is what reads as "cinematic".
        let windowSize = 8.0
        var heroTimes: [Double] = []
        var windowStart = 0.0
        while windowStart < videoDuration {
            let windowEvents = graded.enumerated().filter {
                $0.element.time >= windowStart && $0.element.time < windowStart + windowSize
            }
            if let hero = windowEvents.max(by: { $0.element.intensity < $1.element.intensity }),
               hero.element.intensity > 0.75 {
                graded[hero.offset].intensity = 1.0
                graded[hero.offset].sharpness = max(0.7, graded[hero.offset].sharpness)
                heroTimes.append(hero.element.time)
            }
            windowStart += windowSize
        }

        // Silence-before-impact: remove events in the 0.3s leading up to a hero.
        graded.removeAll { event in
            heroTimes.contains { hero in
                event.time < hero && hero - event.time < 0.3
            }
        }

        // Rumble tail after each hero: one continuous event with a decay
        // curve (thud → fading rumble). Sustained ambient rumble is handled
        // by the envelope layer, not here.
        var tails: [HapticEvent] = []
        for hero in heroTimes where hero + 0.5 < videoDuration - 1.0 {
            tails.append(HapticEvent(
                time: hero + 0.03, intensity: 1.0, sharpness: 0.12,
                duration: 0.45, type: .continuous,
                intensityCurve: [
                    HapticCurvePoint(time: 0, value: 0.7),
                    HapticCurvePoint(time: 0.18, value: 0.35),
                    HapticCurvePoint(time: 0.45, value: 0.0),
                ]))
        }

        graded.append(contentsOf: tails)
        graded.sort { $0.time < $1.time }

        print("✨ Awe grading: \(heroTimes.count) hero moments, range \(String(format: "%.2f", lo))→\(String(format: "%.2f", hi)) expanded")
        return graded
    }

    // MARK: - Envelope Layer (waveform-following realism)

    /// Transcodes the audio's low-frequency energy into continuous haptic
    /// events whose intensity FOLLOWS the waveform envelope via curve points,
    /// instead of firing discrete blips. Control rate ≈ 86 Hz from the FFT
    /// hop; fast-attack/slow-release smoothing keeps the rumble "attached"
    /// to the sound the way a real engine or bass line feels.
    private func generateEnvelopeLayer(frames: [AudioAnalysisFrame],
                                       videoDuration: Double,
                                       aiContext: AIVideoContext) -> [HapticEvent] {
        guard frames.count > 8 else { return [] }

        // 1) Perceptual envelope from the haptic-relevant bands.
        //    The rms term is weighted by (1 - centroid) so loud HIGH-pitched
        //    sustained tones (flute, violin) don't produce bass rumble —
        //    only low-centroid energy feeds the bed.
        var env: [Float] = frames.map { f in
            let lfWeight = min(1.0, max(0.2, 1 - f.spectralCentroid))
            let e = 0.6 * f.bandEnergies[0] + 0.5 * f.bandEnergies[1] + 0.4 * f.rms * lfWeight
            return pow(min(1, e), 1.5)   // sink the noise floor, keep peaks
        }

        // 2) Asymmetric smoothing: ~fast attack, slow release.
        var s: Float = 0
        for i in env.indices {
            let alpha: Float = env[i] > s ? 0.5 : 0.06
            s += alpha * (env[i] - s)
            env[i] = s
        }

        // Engine-class detection per frame — engines get special treatment
        // throughout: no adaptation fade (the sustain IS the content),
        // firing-pulse grain, and an RPM sharpness sweep.
        let engineActive: [Bool] = frames.map {
            aiContext.isLabelActive(matching: "engine", at: $0.time, minConfidence: 0.35)
        }

        // 2b) Adaptation decay: skin adapts to constant vibration within
        //     ~2 s, so an unwavering drone just feels like noise ("persisted
        //     for no reason"). Subtract a slow baseline (τ≈2 s) — swells and
        //     changes survive, static sustain fades toward silence.
        //     Engines are exempt: a held rev must NOT fade.
        var baseline: Float = 0
        let baselineAlpha: Float = 0.006   // ≈ 11.6ms hop / 2s
        for i in env.indices {
            baseline += baselineAlpha * (env[i] - baseline)
            env[i] = max(0, env[i] - (engineActive[i] ? 0.08 : 0.45) * baseline)
        }

        // 2c) Engine grain: real engines flutter at cylinder-firing rate.
        //     Superimpose amplitude modulation whose frequency rises with
        //     the spectral centroid (higher RPM → faster flutter). This is
        //     the "texture" that separates a vroom from a volume swell.
        for i in env.indices where engineActive[i] && env[i] > 0.05 {
            let flutterHz = 16 + 24 * Double(min(1, frames[i].spectralCentroid * 3))
            let mod = Float(sin(2 * Double.pi * flutterHz * frames[i].time))
            env[i] = min(1, env[i] * (1 + 0.22 * mod))
        }

        // 3) Dialogue gate: silence the bed under speech (unless an
        //    impact-class sound is firing at the same moment).
        for i in env.indices {
            let t = frames[i].time
            if aiContext.matchingImpactClass(at: t, minConfidence: 0.5) == nil,
               aiContext.isLabelActive(matching: "speech", at: t, minConfidence: 0.7) {
                env[i] = 0
            }
        }

        // 4) Segment active regions (gate 0.1), bridge gaps < 0.25 s,
        //    drop regions shorter than 0.3 s, cap each at 8 s.
        let gate: Float = 0.1
        var regions: [(start: Int, end: Int)] = []
        var regionStart: Int? = nil
        for i in env.indices {
            if env[i] > gate {
                if regionStart == nil { regionStart = i }
            } else if let start = regionStart {
                regions.append((start, i - 1)); regionStart = nil
            }
        }
        if let start = regionStart { regions.append((start, env.count - 1)) }

        var merged: [(start: Int, end: Int)] = []
        for r in regions {
            if let last = merged.last,
               frames[r.start].time - frames[last.end].time < 0.25 {
                merged[merged.count - 1].end = r.end
            } else {
                merged.append(r)
            }
        }

        // 5) Emit one continuous event per region with a downsampled
        //    intensity curve (~1 point / 46 ms, redundant points dropped).
        var events: [HapticEvent] = []
        for region in merged {
            let startTime = frames[region.start].time
            var endTime = min(frames[region.end].time, startTime + 8.0, videoDuration - 1.0)
            guard endTime - startTime >= 0.3 else { continue }

            let isEngineRegion = (region.start...region.end)
                .lazy.filter { engineActive[$0] }.count
                > (region.end - region.start + 1) / 3

            var points: [HapticCurvePoint] = []
            var lastValue: Float = -1
            var i = region.start
            // Engine grain flutters at 16-40Hz; the normal 46ms stride would
            // alias it away, so engine regions emit every frame (~86Hz) and
            // skip the redundancy filter.
            let stride = isEngineRegion ? 1 : 4
            let minDelta: Float = isEngineRegion ? 0.005 : 0.02
            while i <= region.end, frames[i].time <= endTime {
                // Perceptual linearization at the FINAL mapping: Core Haptics
                // intensity is ~quadratic, so sqrt makes the envelope track
                // the audio linearly as felt. 0.8× keeps the headroom cap so
                // accents still stand out above the bed. Applied once, here.
                let v = 0.8 * sqrt(min(1, env[i]))
                if abs(v - lastValue) >= minDelta || points.isEmpty {
                    points.append(HapticCurvePoint(time: frames[i].time - startTime, value: v))
                    lastValue = v
                }
                i += stride
            }
            // Always close the curve at zero so nothing lingers.
            points.append(HapticCurvePoint(time: endTime - startTime, value: 0))
            guard points.count >= 2 else { continue }

            endTime = startTime + points.last!.time
            let meanCentroid = frames[region.start...region.end].map(\.spectralCentroid).reduce(0, +) / Float(region.end - region.start + 1)
            let meanSharpness = sharpness(forCentroid: meanCentroid)

            // RPM sweep: engines get a sharpness curve tracking the spectral
            // centroid (~1 point / 0.15s), riding from low rumble up toward
            // the ~0.73 resonance where the Taptic Engine punches hardest.
            // Rising pitch you can FEEL is what reads as acceleration.
            var sharpnessPoints: [HapticCurvePoint]? = nil
            if isEngineRegion {
                var sp: [HapticCurvePoint] = []
                var j = region.start
                while j <= region.end, frames[j].time <= endTime {
                    let target = min(0.75, max(0.15, sharpness(forCentroid: frames[j].spectralCentroid)))
                    sp.append(HapticCurvePoint(time: frames[j].time - startTime, value: target))
                    j += 13   // ≈ every 0.15s — sharpness sweeps are slow
                }
                if sp.count >= 2 { sharpnessPoints = sp }
            }

            events.append(HapticEvent(
                time: startTime,
                intensity: 1.0,          // gain; the curve carries the shape
                sharpness: isEngineRegion ? 0.3 : min(0.4, meanSharpness),
                duration: endTime - startTime,
                type: .continuous,
                intensityCurve: points,
                sharpnessCurve: sharpnessPoints
            ))
        }

        print("🌊 Envelope layer: \(events.count) waveform-following regions")
        return events
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
