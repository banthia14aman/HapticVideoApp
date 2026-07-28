//
//  UploadView.swift
//  HapticVideoApp
//
//  Modern 2025 upload UI with drag-drop area and progress animations
//

import SwiftUI
import PhotosUI
import AVKit

struct UploadView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @StateObject private var uploadViewModel = UploadViewModel()
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var videoTitle = ""
    @State private var videoDescription = ""
    @State private var selectedVideoURL: URL?
    @State private var selectedThumbnail: UIImage?
    @State private var showVideoPicker = false
    @State private var suggestedTitle: String?
    @State private var showLongVideoAlert = false
    @State private var showSavedToast = false

    private static let titleLimit = 60
    private static let longVideoThreshold: Double = 180
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                AppColors.backgroundDark
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        headerSection
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                        
                        if let thumbnail = selectedThumbnail {
                            videoPreviewCard(thumbnail: thumbnail)
                                .padding(.horizontal, 20)
                        } else {
                            videoSelectionArea
                                .padding(.horizontal, 20)
                        }
                        
                        if selectedVideoURL != nil {
                            detailsForm
                                .padding(.horizontal, 20)
                        }
                        
                        if uploadViewModel.isUploading || uploadViewModel.isGeneratingHaptics {
                            uploadProgressView
                                .padding(.horizontal, 20)
                        }
                        
                        Spacer()
                            .frame(height: 120)
                    }
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Upload")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.textPrimary)
                }
            }
            .toolbarBackground(AppColors.backgroundDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .photosPicker(isPresented: $showVideoPicker, selection: $selectedItem, matching: .videos)
            .onChange(of: selectedItem) { oldValue, newItem in
                Task {
                    await loadVideo(from: newItem)
                }
            }
            .fullScreenCover(isPresented: $uploadViewModel.showHapticEditor) {
                if let pattern = uploadViewModel.generatedPattern,
                   let videoURL = uploadViewModel.currentVideoURL {
                    HapticEditorView(
                        pattern: .constant(pattern),
                        videoURL: videoURL,
                        videoDuration: uploadViewModel.videoDuration,
                        onSave: { editedPattern in
                            Task {
                                await finalizeUpload(with: editedPattern)
                            }
                        },
                        onCancel: {
                            // Backing out of the editor without saving used to
                            // leave isUploading stuck true → upload UI soft-locked.
                            uploadViewModel.isUploading = false
                            uploadViewModel.uploadProgress = 0
                            uploadViewModel.isGeneratingHaptics = false
                        }
                    )
                }
            }
            .alert("Error", isPresented: .constant(uploadViewModel.errorMessage != nil)) {
                Button("OK") {
                    uploadViewModel.errorMessage = nil
                }
            } message: {
                Text(uploadViewModel.errorMessage ?? "")
            }
            .alert("Long Video", isPresented: $showLongVideoAlert) {
                Button("Continue") { }
                Button("Cancel", role: .cancel) { resetUpload() }
            } message: {
                Text("This video is over 3 minutes, so haptic generation will take a while longer. Continue anyway?")
            }
            .overlay(alignment: .bottom) {
                if showSavedToast {
                    Text("Saved to your feed ✓")
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.textPrimary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(AppColors.backgroundSecondary)
                        .clipShape(Capsule())
                        .shadow(radius: 8)
                        .padding(.bottom, 100)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            UIHaptics.prepare()
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Create Haptic Video")
                .font(AppTypography.title)
                .foregroundColor(AppColors.textPrimary)
            
            Text("Upload a video and we'll generate haptics")
                .font(AppTypography.subheadline)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Video Selection Area
    
    private var videoSelectionArea: some View {
        VStack(spacing: 20) {
            Button {
                UIHaptics.buttonTapMedium()
                showVideoPicker = true
            } label: {
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(AppColors.primary.opacity(0.15))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(AppColors.primaryGradient)
                    }
                    
                    VStack(spacing: 8) {
                        Text("Select Video")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.textPrimary)
                        
                        Text("Choose from your library")
                            .font(AppTypography.subheadline)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(AppColors.backgroundSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                                .foregroundColor(AppColors.backgroundTertiary)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            
        }
    }
    
    // MARK: - Video Preview Card
    
    private func videoPreviewCard(thumbnail: UIImage) -> some View {
        VStack(spacing: 16) {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fill)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                
                // Duration bottom-left, close top-right — they overlapped
                // when both sat in the top-right corner.
                Text(formatDuration(uploadViewModel.videoDuration))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                Button {
                    UIHaptics.buttonTap()
                    resetUpload()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .padding(12)
            }
            .frame(height: 200)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Video Selected")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                    
                    Text(formatDuration(uploadViewModel.videoDuration) + " duration")
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.textPrimary)
                }
                
                Spacer()
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(AppColors.success)
            }
        }
        .padding(16)
        .background(AppColors.backgroundSecondary)
        .cornerRadius(20)
    }
    
    // MARK: - Details Form
    
    private var detailsForm: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("TITLE")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(AppColors.textTertiary)

                    Spacer()

                    Text("\(videoTitle.count)/\(Self.titleLimit)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(videoTitle.count > Self.titleLimit ? AppColors.error : AppColors.textTertiary)
                }

                ModernTextField(
                    icon: "textformat",
                    placeholder: suggestedTitle ?? "Enter video title",
                    text: $videoTitle
                )
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("DESCRIPTION")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(AppColors.textTertiary)
                
                TextEditor(text: $videoDescription)
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(16)
                    .frame(height: 100)
                    .background(AppColors.backgroundTertiary)
                    .cornerRadius(16)
            }
            
            VStack(spacing: 8) {
                Button {
                    Task {
                        await startUpload()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.badge.plus")
                        Text("Generate Haptics & Upload")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(uploadDisabledReason != nil || uploadViewModel.isUploading)
                .opacity(uploadDisabledReason != nil ? 0.6 : 1)

                if let reason = uploadDisabledReason {
                    Text(reason)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textTertiary)
                }
            }
        }
    }

    private var uploadDisabledReason: String? {
        if selectedVideoURL == nil { return "Pick a video first" }
        if videoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add a title" }
        if videoTitle.count > Self.titleLimit { return "Keep the title under \(Self.titleLimit) characters" }
        return nil
    }
    
    // MARK: - Upload Progress View
    
    private var uploadProgressView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(AppColors.backgroundTertiary, lineWidth: 8)
                    .frame(width: 100, height: 100)
                
                Circle()
                    .trim(from: 0, to: totalProgress)
                    .stroke(
                        AppColors.primaryGradient,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: totalProgress)
                
                VStack(spacing: 4) {
                    Text("\(Int(totalProgress * 100))%")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(AppColors.textPrimary)
                    
                    if uploadViewModel.isGeneratingHaptics {
                        Image(systemName: "waveform")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.primary)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Self.stages.indices, id: \.self) { i in
                    HStack(spacing: 12) {
                        Image(systemName: i < currentStageIndex ? "checkmark.circle.fill" : Self.stages[i].icon)
                            .font(.system(size: 16))
                            .foregroundColor(i < currentStageIndex ? AppColors.success :
                                             i == currentStageIndex ? AppColors.primary : AppColors.textTertiary)
                            .frame(width: 22)

                        Text(Self.stages[i].label)
                            .font(AppTypography.subheadline)
                            .foregroundColor(i == currentStageIndex ? AppColors.textPrimary : AppColors.textTertiary)

                        Spacer()

                        if i == currentStageIndex {
                            ProgressView()
                                .tint(AppColors.primary)
                                .scaleEffect(0.7)
                        }
                    }
                }

                if currentStageIndex == Self.stages.count {
                    HStack(spacing: 12) {
                        Image(systemName: "icloud.and.arrow.up")
                            .font(.system(size: 16))
                            .foregroundColor(AppColors.primary)
                            .frame(width: 22)

                        Text("Saving to your feed")
                            .font(AppTypography.subheadline)
                            .foregroundColor(AppColors.textPrimary)

                        Spacer()

                        ProgressView()
                            .tint(AppColors.primary)
                            .scaleEffect(0.7)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(AppColors.backgroundSecondary)
        .cornerRadius(24)
    }

    // MARK: - Helpers

    private static let stages: [(icon: String, label: String, start: Double)] = [
        ("waveform", "Analyzing audio", 0.3),
        ("ear", "Detecting sounds", 0.6),
        ("video", "Analyzing motion", 0.85),
        ("hand.tap", "Building haptics", 0.92)
    ]

    /// Index of the active stage; Self.stages.count when generation is done (uploading).
    private var currentStageIndex: Int {
        guard uploadViewModel.isGeneratingHaptics else { return Self.stages.count }
        let p = uploadViewModel.hapticGenerationProgress
        return Self.stages.lastIndex(where: { p >= $0.start }) ?? 0
    }

    private var totalProgress: Double {
        if uploadViewModel.isGeneratingHaptics {
            return uploadViewModel.hapticGenerationProgress * 0.8
        } else if uploadViewModel.isUploading {
            return 0.8 + (uploadViewModel.uploadProgress * 0.2)
        }
        return 0
    }
    
    private func loadVideo(from item: PhotosPickerItem?) async {
        guard let item = item else { return }
        
        do {
            if let video = try await item.loadTransferable(type: VideoTransferable.self) {
                let url = video.url
                VideoTransferable.discardDraft(at: selectedVideoURL)  // replaced pick
                VideoTransferable.sweepStaleDrafts()
                selectedVideoURL = url
                uploadViewModel.currentVideoURL = url
                suggestedTitle = video.originalName

                // Generate thumbnail (async API — copyCGImage is deprecated
                // and blocked the main thread)
                let asset = AVURLAsset(url: url)
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true

                let cgImage = try await imageGenerator.image(at: .zero).image
                selectedThumbnail = UIImage(cgImage: cgImage)

                // Get duration
                let duration = try await asset.load(.duration)
                uploadViewModel.videoDuration = CMTimeGetSeconds(duration)

                UIHaptics.success()

                if uploadViewModel.videoDuration > Self.longVideoThreshold {
                    showLongVideoAlert = true
                }
            }
        } catch {
            print("Error loading video: \(error)")
            // Surface it — a silent console print looked like "nothing happened".
            uploadViewModel.errorMessage =
                "Couldn't load that video. If it's stored in iCloud, open it once in Photos to download it, then try again."
            VideoTransferable.discardDraft(at: selectedVideoURL)
            selectedVideoURL = nil
            selectedThumbnail = nil
            UIHaptics.error()
        }
    }
    
    private func startUpload() async {
        guard let user = authViewModel.currentUser,
              let videoURL = selectedVideoURL else { return }
        
        UIHaptics.buttonTapMedium()
        
        await uploadViewModel.uploadVideo(
            videoURL: videoURL,
            title: videoTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            description: videoDescription.isEmpty ? nil : videoDescription,
            uploaderID: user.id,
            uploaderUsername: user.username
        )
    }
    
    private func finalizeUpload(with pattern: HapticPattern) async {
        await uploadViewModel.finalizeUpload(editedPattern: pattern)
        
        if uploadViewModel.errorMessage == nil {
            UIHaptics.success()
            resetUpload()
            withAnimation { showSavedToast = true }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { showSavedToast = false }
        } else {
            UIHaptics.error()
        }
    }
    
    private func resetUpload() {
        VideoTransferable.discardDraft(at: selectedVideoURL)
        selectedItem = nil
        selectedVideoURL = nil
        selectedThumbnail = nil
        suggestedTitle = nil
        videoTitle = ""
        videoDescription = ""
        uploadViewModel.currentVideoURL = nil
        uploadViewModel.generatedPattern = nil
        uploadViewModel.isUploading = false
        uploadViewModel.isGeneratingHaptics = false
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Video Transferable

struct VideoTransferable: Transferable {
    let url: URL
    var originalName: String? = nil

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            // Documents, NOT tmp — iOS purges tmp/ on backgrounding, which
            // deleted the picked video out from under the editor timeline.
            // KEEP the original extension: AVURLAsset infers the container
            // type from it, and renaming an .mp4 to .mov makes asset loading
            // fail with -11800/-17913 (assetProperty_AssetType).
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let draftURL = docs.appendingPathComponent("draft-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: draftURL)

            // A zero-byte copy (iCloud asset that never materialized) should
            // fail here, not as a cryptic AVFoundation error later.
            let size = (try? draftURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size > 0 else {
                try? FileManager.default.removeItem(at: draftURL)
                throw CocoaError(.fileReadCorruptFile)
            }

            let name = received.file.deletingPathExtension().lastPathComponent
            return Self(url: draftURL, originalName: name.isEmpty ? nil : name)
        }
    }

    /// Removes a draft file created by the importer (no-op for other URLs).
    static func discardDraft(at url: URL?) {
        guard let url, url.lastPathComponent.hasPrefix("draft-") else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Sweeps drafts orphaned by force-quits (older than 48h).
    static func sweepStaleDrafts() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cutoff = Date().addingTimeInterval(-48 * 3600)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: docs, includingPropertiesForKeys: [.creationDateKey]) else { return }
        for file in files where file.lastPathComponent.hasPrefix("draft-") {
            let created = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if created < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}

#Preview {
    UploadView()
        .environmentObject(AuthenticationViewModel())
}
