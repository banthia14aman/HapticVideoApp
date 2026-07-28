//
//  VideoMotionAnalyzer.swift
//  HapticVideoApp
//
//  Phase-1 AI gate: sample optical flow magnitudes across the video to
//  detect motion spikes the audio missed (silent action, no Foley, etc).
//

import Foundation
import Vision
import AVFoundation
import CoreVideo
import CoreImage
import CoreGraphics

struct MotionSample: Equatable, Sendable {
    let time: Double      // seconds
    let magnitude: Float  // mean optical-flow magnitude in this frame pair
    /// True when this frame pair is a hard cut/transition (global outlier motion).
    var isSceneCut: Bool = false
    /// Share of motion in the top-4 of 16 grid cells. ~0.25 = uniform (camera
    /// pan/shake), →1.0 = concentrated (subject motion). Default 1 = "trust it".
    var motionConcentration: Float = 1.0
}

final class VideoMotionAnalyzer {

    /// Sample the video at `fps` Hz, compute optical flow between adjacent
    /// samples, and return mean motion magnitude per sample.
    func analyze(asset: AVURLAsset, fps: Double = 4.0) async throws -> [MotionSample] {
        let fps = min(max(fps, 1), 10) // ponytail: hard cap analysis rate; raise if quality ever demands
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { return [] }

        let count = max(2, Int(duration * fps))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
        // Downscale aggressively — motion magnitude doesn't need high res.
        generator.maximumSize = CGSize(width: 160, height: 90)

        var raw: [(time: Double, magnitude: Float, concentration: Float)] = []
        var previousBuffer: CVPixelBuffer?

        for i in 0..<count {
            let t = Double(i) / fps
            let cmTime = CMTime(seconds: t, preferredTimescale: 600)

            guard let cgImage = await safeImage(generator: generator, at: cmTime) else {
                continue
            }
            guard let pb = cgImage.toPixelBuffer() else { continue }

            if let prev = previousBuffer {
                if let (mag, conc) = try? Self.flowStats(previous: prev, current: pb) {
                    raw.append((t, mag, conc))
                }
            }
            previousBuffer = pb
        }

        // Post-pass: scene cuts = strong global outliers; other global motion
        // (camera pan/shake) inflates magnitude with no haptic-worthy event.
        let mean = raw.isEmpty ? 0 : raw.map(\.magnitude).reduce(0, +) / Float(raw.count)
        let variance = raw.isEmpty ? 0 : raw.map { ($0.magnitude - mean) * ($0.magnitude - mean) }.reduce(0, +) / Float(raw.count)
        let cutThreshold = max(mean + 3 * variance.squareRoot(), 2 * mean)
        let globalThreshold: Float = 0.4 // top-4/16 cells; uniform frame ≈ 0.25

        let samples: [MotionSample] = raw.map { s in
            let isGlobal = s.concentration < globalThreshold
            let isCut = isGlobal && variance > 0 && s.magnitude > cutThreshold
            // ponytail: uniform flow = camera motion, dampen; homography check if this misfires
            let magnitude = (isGlobal && !isCut) ? s.magnitude * 0.4 : s.magnitude
            return MotionSample(time: s.time,
                                magnitude: magnitude,
                                isSceneCut: isCut,
                                motionConcentration: s.concentration)
        }

        print("🎬 VideoMotionAnalyzer: \(samples.count) samples, \(samples.filter(\.isSceneCut).count) cuts (fps=\(fps), duration=\(String(format: "%.1f", duration))s)")
        return samples
    }

    // MARK: - Helpers

    private func safeImage(generator: AVAssetImageGenerator, at time: CMTime) async -> CGImage? {
        do {
            let result = try await generator.image(at: time)
            return result.image
        } catch {
            return nil
        }
    }

    private static func flowStats(previous: CVPixelBuffer, current: CVPixelBuffer) throws -> (magnitude: Float, concentration: Float) {
        let request = VNGenerateOpticalFlowRequest(targetedCVPixelBuffer: current, options: [:])
        // .low accuracy is ~10× faster and plenty for "is the screen moving a lot"
        request.computationAccuracy = .low
        request.outputPixelFormat = kCVPixelFormatType_TwoComponent32Float

        let handler = VNImageRequestHandler(cvPixelBuffer: previous, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first else { return (0, 1) }
        let cells = cellMeans(observation.pixelBuffer)

        let total = cells.reduce(0, +)
        guard total > 0 else { return (0, 1) }
        let magnitude = total / Float(cells.count)
        let top4 = cells.sorted(by: >).prefix(4).reduce(0, +)
        return (magnitude, top4 / total)
    }

    /// Mean of √(dx² + dy²) per cell of a 4x4 grid, sampling every Nth pixel.
    private static func cellMeans(_ buffer: CVPixelBuffer) -> [Float] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, height > 0, let base = CVPixelBufferGetBaseAddress(buffer) else {
            return [Float](repeating: 0, count: 16)
        }

        let pixelStride = 4
        var totals = [Float](repeating: 0, count: 16)
        var counts = [Int](repeating: 0, count: 16)

        for y in Swift.stride(from: 0, to: height, by: pixelStride) {
            let rowPtr = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float.self)
            let row = min(3, y * 4 / height)
            for x in Swift.stride(from: 0, to: width, by: pixelStride) {
                let dx = rowPtr[x * 2]
                let dy = rowPtr[x * 2 + 1]
                let cell = row * 4 + min(3, x * 4 / width)
                totals[cell] += sqrtf(dx * dx + dy * dy)
                counts[cell] += 1
            }
        }

        return zip(totals, counts).map { $1 > 0 ? $0 / Float($1) : 0 }
    }
}

// MARK: - CGImage → CVPixelBuffer

private extension CGImage {
    func toPixelBuffer() -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pb
        )
        guard status == kCVReturnSuccess, let buffer = pb else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
                       | CGBitmapInfo.byteOrder32Little.rawValue

        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        ctx.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
