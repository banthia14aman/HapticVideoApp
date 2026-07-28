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
    
    private let dataStore = AppBackend.store
    
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
            print("⚠️ No audio track — running motion-only analysis")
            // Even without audio, try motion-driven haptics from video.
            let motionOnlySamples = (try? await VideoMotionAnalyzer().analyze(asset: asset)) ?? []
            let context = AIVideoContext(soundHits: [],
                                         motionSamples: motionOnlySamples,
                                         videoDuration: duration)
            let analyzer = AudioAnalyzer()
            var events = analyzer.generateHapticEvents(from: [],
                                                       videoDuration: duration,
                                                       aiContext: context)
            if events.isEmpty {
                events = generateRhythmicHaptics(duration: duration)
            }
            events = validateHapticEvents(events, videoDuration: duration)
            hapticGenerationProgress = 1.0
            return events
        }

        // Extract audio samples using existing method
        let samples = try await extractAudioSamples(from: asset, audioTrack: audioTrack, duration: duration)
        let analyzer = AudioAnalyzer()

        print("🤖 Phase-1 AI pipeline: classical DSP + sound classification + optical-flow gate")

        // Kick off the three analyzers in parallel.
        let audioTask = Task.detached(priority: .userInitiated) { [weak self] () -> [AudioAnalysisFrame] in
            analyzer.analyzeAudio(samples: samples, videoDuration: duration) { progress in
                Task { @MainActor in
                    self?.hapticGenerationProgress = 0.3 + progress * 0.3   // 30% → 60%
                }
            }
        }

        let soundTask = Task.detached(priority: .userInitiated) { () -> [SoundHit] in
            await SoundClassifier().classify(samples: samples)
        }

        let motionTask = Task.detached(priority: .userInitiated) { () -> [MotionSample] in
            (try? await VideoMotionAnalyzer().analyze(asset: asset)) ?? []
        }

        let frames = await audioTask.value
        await MainActor.run { [weak self] in self?.hapticGenerationProgress = 0.7 }

        let soundHits = await soundTask.value
        await MainActor.run { [weak self] in self?.hapticGenerationProgress = 0.85 }

        let motionSamples = await motionTask.value
        await MainActor.run { [weak self] in self?.hapticGenerationProgress = 0.92 }

        print("📊 Audio frames: \(frames.count), onsets: \(frames.filter { $0.isOnset }.count)")
        let uniqueLabels = Set(soundHits.map { $0.label })
        print("🎙️ Sound hits: \(soundHits.count) (\(uniqueLabels.count) unique labels)")
        print("🎬 Motion samples: \(motionSamples.count)")

        let aiContext = AIVideoContext(soundHits: soundHits,
                                       motionSamples: motionSamples,
                                       videoDuration: duration)

        var events = analyzer.generateHapticEvents(from: frames,
                                                   videoDuration: duration,
                                                   aiContext: aiContext)

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

            // Prepare local data
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
                videoURL: "",        // Populated by CloudDataStore after upload
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

            try await dataStore.uploadVideo(
                video: video,
                videoData: videoData,
                videoFileExtension: videoURL.pathExtension,
                thumbnailData: thumbnailData,
                hapticsData: hapticsData
            )

            uploadProgress = 1.0
            isUploading = false
            showHapticEditor = false
            generatedPattern = nil
            currentVideoURL = nil
            print("✅ Cloud Upload complete!")

        } catch {
            errorMessage = "Upload failed: \(error.localizedDescription)"
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
    
    private func extractAudioSamples(from asset: AVURLAsset, audioTrack: AVAssetTrack, duration: Double) async throws -> [Float] {
        let reader = try AVAssetReader(asset: asset)
        
        // Force 44.1 kHz mono — AudioAnalyzer and SoundClassifier compute event
        // times as sampleIndex/44100 on a single channel. Without this, a 48 kHz
        // stereo track makes every audio-derived haptic land ~2.2x early.
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1
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
