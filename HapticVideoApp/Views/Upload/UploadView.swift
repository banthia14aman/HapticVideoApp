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
    @State private var showingRecorder = false
    @State private var selectedVideoURL: URL?
    @State private var selectedThumbnail: UIImage?
    @State private var showVideoPicker = false
    
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
            
            HStack {
                Rectangle()
                    .fill(AppColors.backgroundTertiary)
                    .frame(height: 1)
                
                Text("OR")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textTertiary)
                    .padding(.horizontal, 16)
                
                Rectangle()
                    .fill(AppColors.backgroundTertiary)
                    .frame(height: 1)
            }
            
            Button {
                UIHaptics.buttonTap()
                showingRecorder = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 18))
                    Text("Record New Video")
                        .font(AppTypography.headline)
                }
            }
            .buttonStyle(SecondaryButtonStyle())
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
                
                Text(formatDuration(uploadViewModel.videoDuration))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .padding(12)
                
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
                .offset(y: -8)
            }
            
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
                Text("TITLE")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(AppColors.textTertiary)
                
                ModernTextField(
                    icon: "textformat",
                    placeholder: "Enter video title",
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
            .disabled(videoTitle.isEmpty || uploadViewModel.isUploading)
            .opacity(videoTitle.isEmpty ? 0.6 : 1)
        }
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
            
            VStack(spacing: 8) {
                Text(statusText)
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.textPrimary)
                
                Text(statusSubtext)
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(AppColors.backgroundSecondary)
        .cornerRadius(24)
    }
    
    // MARK: - Helpers
    
    private var totalProgress: Double {
        if uploadViewModel.isGeneratingHaptics {
            return uploadViewModel.hapticGenerationProgress * 0.8
        } else if uploadViewModel.isUploading {
            return 0.8 + (uploadViewModel.uploadProgress * 0.2)
        }
        return 0
    }
    
    private var statusText: String {
        if uploadViewModel.isGeneratingHaptics {
            return "Generating Haptics"
        } else if uploadViewModel.isUploading {
            return "Uploading"
        }
        return "Processing"
    }
    
    private var statusSubtext: String {
        if uploadViewModel.isGeneratingHaptics {
            return "Analyzing audio waveform..."
        } else if uploadViewModel.isUploading {
            return "Almost there..."
        }
        return "Please wait"
    }
    
    private func loadVideo(from item: PhotosPickerItem?) async {
        guard let item = item else { return }
        
        do {
            if let url = try await item.loadTransferable(type: VideoTransferable.self)?.url {
                selectedVideoURL = url
                uploadViewModel.currentVideoURL = url
                
                // Generate thumbnail
                let asset = AVAsset(url: url)
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true
                
                let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
                selectedThumbnail = UIImage(cgImage: cgImage)
                
                // Get duration
                let duration = try await asset.load(.duration)
                uploadViewModel.videoDuration = CMTimeGetSeconds(duration)
                
                UIHaptics.success()
            }
        } catch {
            print("Error loading video: \(error)")
            UIHaptics.error()
        }
    }
    
    private func startUpload() async {
        guard let user = authViewModel.currentUser,
              let videoURL = selectedVideoURL else { return }
        
        UIHaptics.buttonTapMedium()
        
        await uploadViewModel.uploadVideo(
            videoURL: videoURL,
            title: videoTitle,
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
        } else {
            UIHaptics.error()
        }
    }
    
    private func resetUpload() {
        selectedItem = nil
        selectedVideoURL = nil
        selectedThumbnail = nil
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
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            try FileManager.default.copyItem(at: received.file, to: tempURL)
            return Self(url: tempURL)
        }
    }
}

#Preview {
    UploadView()
        .environmentObject(AuthenticationViewModel())
}
