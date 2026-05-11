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
}

final class VideoMotionAnalyzer {

    /// Sample the video at `fps` Hz, compute optical flow between adjacent
    /// samples, and return mean motion magnitude per sample.
    func analyze(asset: AVURLAsset, fps: Double = 4.0) async throws -> [MotionSample] {
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { return [] }

        let count = max(2, Int(duration * fps))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
        // Downscale aggressively — motion magnitude doesn't need high res.
        generator.maximumSize = CGSize(width: 160, height: 90)

        var samples: [MotionSample] = []
        var previousBuffer: CVPixelBuffer?

        for i in 0..<count {
            let t = Double(i) / fps
            let cmTime = CMTime(seconds: t, preferredTimescale: 600)

            guard let cgImage = await safeImage(generator: generator, at: cmTime) else {
                continue
            }
            guard let pb = cgImage.toPixelBuffer() else { continue }

            if let prev = previousBuffer {
                if let mag = try? Self.flowMagnitude(previous: prev, current: pb) {
                    samples.append(MotionSample(time: t, magnitude: mag))
                }
            }
            previousBuffer = pb
        }

        print("🎬 VideoMotionAnalyzer: \(samples.count) samples (fps=\(fps), duration=\(String(format: "%.1f", duration))s)")
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

    private static func flowMagnitude(previous: CVPixelBuffer, current: CVPixelBuffer) throws -> Float {
        let request = VNGenerateOpticalFlowRequest(targetedCVPixelBuffer: current, options: [:])
        // .low accuracy is ~10× faster and plenty for "is the screen moving a lot"
        request.computationAccuracy = .low
        request.outputPixelFormat = kCVPixelFormatType_TwoComponent32Float

        let handler = VNImageRequestHandler(cvPixelBuffer: previous, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first else { return 0 }
        return meanMagnitude(observation.pixelBuffer)
    }

    /// Mean of √(dx² + dy²) over the flow field, sampling every Nth pixel.
    private static func meanMagnitude(_ buffer: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return 0 }

        let pixelStride = 4
        var total: Float = 0
        var count: Int = 0

        for y in Swift.stride(from: 0, to: height, by: pixelStride) {
            let rowPtr = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float.self)
            for x in Swift.stride(from: 0, to: width, by: pixelStride) {
                let dx = rowPtr[x * 2]
                let dy = rowPtr[x * 2 + 1]
                let mag = sqrtf(dx * dx + dy * dy)
                total += mag
                count += 1
            }
        }

        return count > 0 ? total / Float(count) : 0
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
