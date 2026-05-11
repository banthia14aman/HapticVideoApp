//
//  UploadViewModel.swift
//  HapticVideoApp
//

import Foundation
import AVFoundation
import UIKit

@MainActor
class UploadViewModel: ObservableObject {
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0.0
    @Published var isGeneratingHaptics = false
    @Published var hapticGenerationProgress: Double = 0.0
    @Published var errorMessage: String?
    @Published var showHapticEditor = false
    @Published var generatedPattern: HapticPattern?
    @Published var currentVideoURL: URL?
    @Published var videoDuration: Double = 0
    
    private var pendingTitle: String = ""
    private var pendingDescription: String?
    private var pendingUploaderID: String = ""
    private var pendingUploaderUsername: String = ""
    
    // Uses Firebase backend
    private let dataStore = CloudDataStore.shared
    
    func uploadVideo(
        videoURL: URL,
        title: String,
        description: String?,
        uploaderID: String,
        uploaderUsername: String
    ) async {
        isUploading = true
        uploadProgress = 0.0
        errorMessage = nil
        currentVideoURL = videoURL
        
        pendingTitle = title
        pendingDescription = description
        pendingUploaderID = uploaderID
        pendingUploaderUsername = uploaderUsername
        
        do {
            uploadProgress = 0.2
            let duration = try await getVideoDuration(from: videoURL)
            videoDuration = duration
            print("⏱️ Video Duration: \(duration)s")
            
            uploadProgress = 0.3
            isGeneratingHaptics = true
            
            print("🎵 Analyzing audio with advanced FFT...")
            let events = try await generateAdvancedHaptics(for: videoURL, duration: duration)
            
            let videoID = UUID().uuidString
            let metadata = PatternMetadata(
                createdAt: Date(),
                updatedAt: Date(),
                version: "2.0"  // Version bump for new algorithm
            )
            
            generatedPattern = HapticPattern(
                videoID: videoID,
                events: events,
                metadata: metadata
            )
            
            isGeneratingHaptics = false
            uploadProgress = 0.9
            
            print("✅ Generated \(events.count) AI-ANALYZED haptic events")
            
            showHapticEditor = true
            
        } catch {
            errorMessage = "Upload failed: \(error.localizedDescription)"
            isUploading = false
            isGeneratingHaptics = false
            print("❌ Upload error: \(error)")
        }
    }
    
    // MARK: - Advanced Haptic Generation (FFT + Spectral Flux)
    
    private func generateAdvancedHaptics(for videoURL: URL, duration: Double) async throws -> [HapticEvent] {
        let asset = AVURLAsset(url: videoURL)
        
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            print("⚠️ No audio track, using rhythm")
            return generateRhythmicHaptics(duration: duration)
        }
        
        // Extract audio samples using existing method
        let samples = try await extractAudioSamples(from: asset, audioTrack: audioTrack, duration: duration)
        
        // Use advanced analyzer
        let analyzer = AudioAnalyzer()
        
        // Analyze with progress callback
        let frames = analyzer.analyzeAudio(samples: samples, videoDuration: duration) { [weak self] progress in
            Task { @MainActor in
                self?.hapticGenerationProgress = 0.3 + progress * 0.5  // Progress from 30% to 80%
            }
        }
        
        print("📊 Analyzed \(frames.count) audio frames")
        print("📊 Detected \(frames.filter { $0.isOnset }.count) onsets")
        
        // Generate haptic events from analysis
        var events = analyzer.generateHapticEvents(from: frames, videoDuration: duration)
        
        // Validate and clamp events
        events = validateHapticEvents(events, videoDuration: duration)
        
        hapticGenerationProgress = 1.0
        return events
    }
    
    func finalizeUpload(editedPattern: HapticPattern) async {
        guard let videoURL = currentVideoURL else {
            errorMessage = "Video URL not found"
            isUploading = false
            return
        }
        
        do {
            print("☁️ Uploading to cloud...")
            
            var validatedPattern = editedPattern
            validatedPattern.events = validateHapticEvents(editedPattern.events, videoDuration: videoDuration)
            
            // Get local data
            let videoData = try Data(contentsOf: videoURL)
            let thumbnailURL = try await generateThumbnail(from: videoURL)
            let thumbnailData = try Data(contentsOf: thumbnailURL)
            try? FileManager.default.removeItem(at: thumbnailURL)
            
            // Encode haptics
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let hapticsData = try encoder.encode(validatedPattern)
            
            let video = Video(
                id: UUID().uuidString,
                title: pendingTitle,
                videoURL: "", // Will be populated by CloudDataStore
                thumbnailURL: "",
                uploaderID: pendingUploaderID,
                uploaderUsername: pendingUploaderUsername,
                uploadedAt: Date(),
                duration: videoDuration,
                hasHaptics: true,
                hapticsURL: nil,
                views: 0,
                description: pendingDescription
            )
            
            dataStore.uploadVideo(video: video, videoData: videoData, thumbnailData: thumbnailData, hapticsData: hapticsData) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(_):
                        self?.uploadProgress = 1.0
                        self?.isUploading = false
                        self?.showHapticEditor = false
                        self?.generatedPattern = nil
                        self?.currentVideoURL = nil
                        print("✅ Cloud Upload complete!")
                    case .failure(let error):
                        self?.errorMessage = "Cloud Upload failed: \(error.localizedDescription)"
                        self?.isUploading = false
                    }
                }
            }
        } catch {
            errorMessage = "Upload prep failed: \(error.localizedDescription)"
            isUploading = false
        }
    }
    
    private func validateHapticEvents(_ events: [HapticEvent], videoDuration: Double) -> [HapticEvent] {
        var validatedEvents: [HapticEvent] = []
        let safetyMargin: Double = 1.0 // Stop haptics 1 second before video ends
        
        for var event in events {
            // Skip events that start too close to the end
            guard event.time < videoDuration - safetyMargin else {
                print("⚠️ Skipping event at \(event.time)s - too close to end")
                continue
            }
            
            // Calculate how much time is available
            let availableTime = videoDuration - safetyMargin - event.time
            
            // Clamp duration for continuous events
            if event.type == .continuous && event.duration > 0 {
                if event.duration > availableTime {
                    event.duration = max(0.05, availableTime)
                    print("✂️ Truncated continuous event at \(event.time)s to duration \(event.duration)s")
                }
            }
            
            validatedEvents.append(event)
        }
        
        print("✅ Validated: \(validatedEvents.count) of \(events.count) events")
        return validatedEvents
    }
    
    private func generateAudioAnalyzedHaptics(for videoURL: URL, duration: Double) async throws -> [HapticEvent] {
        let asset = AVURLAsset(url: videoURL)
        
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            print("⚠️ No audio track, using rhythm")
            return generateRhythmicHaptics(duration: duration)
        }
        
        print("🎵 Analyzing audio")
        let audioSamples = try await extractAudioSamples(from: asset, audioTrack: audioTrack, duration: duration)
        let events = analyzeAudioAndGenerateHaptics(samples: audioSamples, videoDuration: duration)
        
        return events
    }
    
    private func extractAudioSamples(from asset: AVURLAsset, audioTrack: AVAssetTrack, duration: Double) async throws -> [Float] {
        let reader = try AVAssetReader(asset: asset)
        
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()
        
        var samples: [Float] = []
        let sampleRate: Float = 44100.0
        
        while let sampleBuffer = output.copyNextSampleBuffer() {
            if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                let length = CMBlockBufferGetDataLength(blockBuffer)
                var data = Data(count: length)
                
                let _ = data.withUnsafeMutableBytes { buffer in
                    CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: buffer.baseAddress!)
                }
                
                let int16Samples = data.withUnsafeBytes { $0.bindMemory(to: Int16.self) }
                for sample in int16Samples {
                    samples.append(Float(sample) / Float(Int16.max))
                }
                
                hapticGenerationProgress = min(0.9, Double(samples.count) / Double(sampleRate * Float(duration)))
            }
        }
        
        reader.cancelReading()
        return samples
    }
    
    private func analyzeAudioAndGenerateHaptics(samples: [Float], videoDuration: Double) -> [HapticEvent] {
        var events: [HapticEvent] = []
        
        let windowSize = 4410
        let hopSize = 2205
        var currentTime: Double = 0
        let timeIncrement = Double(hopSize) / 44100.0
        
        var windowIndex = 0
        var previousEnergy: Double = 0
        var lastContinuousTime: Double = -1.0
        
        while windowIndex + windowSize < samples.count {
            let window = Array(samples[windowIndex..<min(windowIndex + windowSize, samples.count)])
            
            let energy = calculateRMS(window)
            let brightness = calculateSpectralCentroid(window)
            let isTransient = energy > previousEnergy * 1.5 && energy > 0.2
            
            if energy > 0.15 {
                var newEvent: HapticEvent?
                
                if isTransient {
                    newEvent = HapticEvent(
                        time: currentTime,
                        intensity: Float(min(1.0, energy * 3.0)),
                        sharpness: Float(min(1.0, brightness)),
                        duration: 0.0,
                        type: .transient
                    )
                } else if energy > 0.4 {
                    newEvent = HapticEvent(
                        time: currentTime,
                        intensity: Float(min(1.0, energy * 2.5)),
                        sharpness: Float(min(0.6, brightness * 0.8)),
                        duration: 0.0,
                        type: .impact
                    )
                } else if energy > 0.25 {
                    let timeSinceLastContinuous = currentTime - lastContinuousTime
                    
                    if timeSinceLastContinuous > 0.3 || lastContinuousTime < 0 {
                        // Clamp duration to not exceed available time
                        let availableTime = videoDuration - 1.0 - currentTime
                        let safeDuration = min(0.2, max(0.05, availableTime))
                        
                        if safeDuration > 0.05 {
                            newEvent = HapticEvent(
                                time: currentTime,
                                intensity: Float(min(0.9, energy * 2.0)),
                                sharpness: Float(min(0.5, brightness * 0.7)),
                                duration: safeDuration,
                                type: .continuous
                            )
                            lastContinuousTime = currentTime
                        }
                    }
                }
                
                if let event = newEvent {
                    let eventEndTime = event.time + event.duration
                    if eventEndTime <= videoDuration - 0.5 {
                        events.append(event)
                    }
                }
            }
            
            previousEnergy = energy
            windowIndex += hopSize
            currentTime += timeIncrement
            
            if currentTime >= videoDuration - 1.0 {
                break
            }
        }
        
        hapticGenerationProgress = 1.0
        print("✅ Generated \(events.count) haptics")
        return events
    }
    
    private func calculateRMS(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        return sqrt(samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count))
    }
    
    private func calculateSpectralCentroid(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        
        var highFreqEnergy: Double = 0
        var totalEnergy: Double = 0
        
        for (i, sample) in samples.enumerated() {
            let weight = Double(i) / Double(samples.count)
            let sampleValue = Double(abs(sample))
            highFreqEnergy += sampleValue * weight
            totalEnergy += sampleValue
        }
        
        return totalEnergy > 0 ? (highFreqEnergy / totalEnergy) : 0
    }
    
    private func generateRhythmicHaptics(duration: Double) -> [HapticEvent] {
        var events: [HapticEvent] = []
        let beatInterval = 0.5
        var currentTime: Double = 0
        
        while currentTime < duration - 0.5 {
            events.append(HapticEvent(
                time: currentTime,
                intensity: 0.7,
                sharpness: 0.5,
                duration: 0.0,
                type: .impact
            ))
            currentTime += beatInterval
        }
        
        return events
    }
    
    private func saveVideoFile(_ sourceURL: URL) throws -> URL {
        let documentsDir = dataStore.getDocumentsDirectory()
        let filename = "\(UUID().uuidString).mov"
        let destinationURL = documentsDir.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }
    
    private func generateThumbnail(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        let time = CMTime(seconds: 1.0, preferredTimescale: 600)
        
        // Use async method for iOS 18+
        let cgImage = try await imageGenerator.image(at: time).image
        let uiImage = UIImage(cgImage: cgImage)
        
        guard let imageData = uiImage.jpegData(compressionQuality: 0.7) else {
            throw VideoUploadError.thumbnailGenerationFailed
        }
        
        // Fallback local temp storage for the thumbnail image creation
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "\(UUID().uuidString)_thumb.jpg"
        let thumbnailURL = tempDir.appendingPathComponent(filename)
        try imageData.write(to: thumbnailURL)
        
        return thumbnailURL
    }
    
    private func getVideoDuration(from videoURL: URL) async throws -> Double {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        
        guard seconds.isFinite && seconds > 0 else {
            throw VideoUploadError.invalidDuration
        }
        
        return seconds
    }
    
    private func saveHapticPattern(_ pattern: HapticPattern) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(pattern)
        
        let documentsDir = dataStore.getDocumentsDirectory()
        let filename = "\(UUID().uuidString)_haptics.json"
        let hapticsURL = documentsDir.appendingPathComponent(filename)
        try data.write(to: hapticsURL)
        
        print("💾 Saved \(pattern.events.count) haptic events")
        return hapticsURL
    }
}

enum VideoUploadError: LocalizedError {
    case thumbnailGenerationFailed
    case invalidDuration
    
    var errorDescription: String? {
        switch self {
        case .thumbnailGenerationFailed: return "Failed to generate thumbnail"
        case .invalidDuration: return "Invalid video duration"
        }
    }
}
