//
//  SoundClassifier.swift
//  HapticVideoApp
//
//  Phase-1 AI gate: classify audio chunks using Apple's built-in
//  SNClassifySoundRequest. The output is fed to AudioAnalyzer as a
//  semantic filter (suppress dialogue, boost gunshots/glass/etc).
//

import Foundation
import SoundAnalysis
import AVFoundation

struct SoundHit: Equatable, Sendable {
    let time: Double        // window start, seconds
    let endTime: Double     // window end, seconds
    let label: String       // class identifier (e.g. "speech", "gunshot_gunfire")
    let confidence: Double  // 0...1
}

final class SoundClassifier: NSObject, SNResultsObserving, @unchecked Sendable {

    // Results accumulator (protected by lock since SNResultsObserving may
    // call back from an internal queue).
    private let resultsLock = NSLock()
    private var hits: [SoundHit] = []

    /// Classify a buffer of mono float samples using the iOS built-in
    /// 300-class sound classifier. Runs off the main thread.
    func classify(samples: [Float],
                  sampleRate: Double = 44_100,
                  minConfidence: Double = 0.4) async -> [SoundHit] {

        await withCheckedContinuation { (continuation: CheckedContinuation<[SoundHit], Never>) in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: [])
                    return
                }
                let result = self.classifySync(samples: samples,
                                               sampleRate: sampleRate,
                                               minConfidence: minConfidence)
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Sync core

    private func classifySync(samples: [Float],
                              sampleRate: Double,
                              minConfidence: Double) -> [SoundHit] {

        // Guard: any failure path (empty/odd audio, format, request) must
        // return [] silently — never crash the analysis pipeline.
        guard !samples.isEmpty, sampleRate > 0 else { return [] }

        // Reset accumulator
        resultsLock.lock(); hits.removeAll(); resultsLock.unlock()

        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate,
                                         channels: 1,
                                         interleaved: false) else {
            print("⚠️ SoundClassifier: failed to build audio format")
            return []
        }

        let analyzer = SNAudioStreamAnalyzer(format: format)

        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            // 0.5s window with 50% overlap is a good middle ground between
            // localization (small windows) and confidence (large windows).
            request.windowDuration = CMTime(seconds: 0.5, preferredTimescale: 600)
            request.overlapFactor = 0.5
            try analyzer.add(request, withObserver: self)
        } catch {
            print("⚠️ SoundClassifier: failed to add request: \(error)")
            return []
        }

        // Feed samples in chunks
        let chunkSize = 1024
        var framePosition: AVAudioFramePosition = 0
        var idx = 0
        while idx < samples.count {
            let end = min(idx + chunkSize, samples.count)
            let chunkCount = end - idx

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                                frameCapacity: AVAudioFrameCount(chunkCount)) else {
                break
            }
            buffer.frameLength = AVAudioFrameCount(chunkCount)
            if let dst = buffer.floatChannelData?[0] {
                samples.withUnsafeBufferPointer { srcPtr in
                    if let base = srcPtr.baseAddress {
                        dst.update(from: base.advanced(by: idx), count: chunkCount)
                    }
                }
            }

            analyzer.analyze(buffer, atAudioFramePosition: framePosition)
            framePosition += AVAudioFramePosition(chunkCount)
            idx = end
        }
        analyzer.completeAnalysis()

        resultsLock.lock()
        let filtered = hits.filter { $0.confidence >= minConfidence }
            .sorted { $0.time < $1.time }
        resultsLock.unlock()

        let smoothed = Self.mergeAdjacentHits(filtered)
        print("🎙️ SoundClassifier: \(smoothed.count) hits (≥\(Int(minConfidence * 100))% confidence, merged from \(filtered.count))")
        return smoothed
    }

    /// Confidence smoothing: single-window classifications flicker. Merge
    /// same-label hits whose gap is ≤ `maxGap` into one hit spanning both,
    /// keeping the max confidence.
    static func mergeAdjacentHits(_ hits: [SoundHit], maxGap: Double = 0.5) -> [SoundHit] {
        guard hits.count > 1 else { return hits }
        var byLabel: [String: [SoundHit]] = [:]
        for hit in hits { byLabel[hit.label, default: []].append(hit) }

        var merged: [SoundHit] = []
        for (_, group) in byLabel {
            var current = group[0]   // group preserves input (time) order
            for hit in group.dropFirst() {
                if hit.time - current.endTime <= maxGap {
                    current = SoundHit(time: current.time,
                                       endTime: max(current.endTime, hit.endTime),
                                       label: current.label,
                                       confidence: max(current.confidence, hit.confidence))
                } else {
                    merged.append(current)
                    current = hit
                }
            }
            merged.append(current)
        }
        return merged.sorted { $0.time < $1.time }
    }

    // MARK: - SNResultsObserving

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let cr = result as? SNClassificationResult else { return }
        let start = cr.timeRange.start.seconds
        let end = cr.timeRange.end.seconds
        resultsLock.lock()
        defer { resultsLock.unlock() }
        for classification in cr.classifications.prefix(3) {
            hits.append(SoundHit(time: start,
                                 endTime: end,
                                 label: classification.identifier,
                                 confidence: classification.confidence))
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        print("⚠️ SoundClassifier failed: \(error.localizedDescription)")
    }

    func requestDidComplete(_ request: SNRequest) { /* no-op */ }
}
