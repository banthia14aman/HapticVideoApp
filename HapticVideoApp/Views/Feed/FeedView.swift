//
//  FeedView.swift
//  HapticVideoApp
//
//  Modern 2025 video feed with floating cards and haptic feedback
//

import SwiftUI

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @State private var selectedVideo: Video?
    @State private var showPlayer = false
    @State private var sortOption: FeedSortOption = .all
    @State private var searchText = ""

    enum FeedSortOption: String, CaseIterable {
        case all = "All"
        case withHaptics = "With Haptics"
        case mostViewed = "Most Viewed"
        case newest = "Newest"
    }

    // Local search + sort over the fetched videos
    private var displayedVideos: [Video] {
        var videos = viewModel.videos
        if !searchText.isEmpty {
            videos = videos.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        switch sortOption {
        case .all:
            break
        case .withHaptics:
            videos = videos.filter(\.hasHaptics)
        case .mostViewed:
            videos.sort { $0.views > $1.views }
        case .newest:
            videos.sort { $0.uploadedAt > $1.uploadedAt }
        }
        return videos
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                AppColors.backgroundDark
                    .ignoresSafeArea()
                
                if viewModel.isLoading {
                    loadingView
                } else if let error = viewModel.errorMessage {
                    errorStateView(message: error)
                } else if viewModel.videos.isEmpty {
                    emptyStateView
                } else {
                    videoFeed
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.path")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppColors.primary)
                        
                        Text("Feed")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.textPrimary)
                    }
                }
            }
            .toolbarBackground(AppColors.backgroundDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .searchable(text: $searchText, prompt: "Search videos")
            .fullScreenCover(isPresented: $showPlayer) {
                if let video = selectedVideo {
                    VideoPlayerView(video: video)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            UIHaptics.prepare()
            viewModel.fetchVideos()
        }
    }
    
    // MARK: - Video Feed
    
    private var videoFeed: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 20) {
                // Header
                feedHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                
                if displayedVideos.isEmpty {
                    noResultsView
                        .padding(.top, 60)
                }

                // Video Cards
                ForEach(displayedVideos) { video in
                    ModernVideoCard(video: video) {
                        UIHaptics.buttonTapMedium()
                        selectedVideo = video
                        showPlayer = true
                        viewModel.incrementViews(for: video.id)
                    }
                    .simultaneousGesture(
                        // Matches the system long-press that opens the context menu
                        LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                            UIHaptics.selectionChanged()
                        }
                    )
                    .contextMenu {
                        // Owners can delete their own uploads
                        if video.uploaderID == authViewModel.currentUser?.id {
                            Button(role: .destructive) {
                                UIHaptics.deleteEvent()
                                viewModel.deleteVideo(video)
                            } label: {
                                Label("Delete Video", systemImage: "trash")
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                // Bottom Spacing
                Spacer()
                    .frame(height: 100)
            }
        }
        .refreshable {
            UIHaptics.buttonTap()
            await refreshFeed()
        }
    }
    
    // MARK: - Feed Header
    
    private var feedHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Discover")
                    .font(AppTypography.title)
                    .foregroundColor(AppColors.textPrimary)
                
                Text("\(displayedVideos.count) haptic videos")
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            // Sort / Filter Menu
            Menu {
                ForEach(FeedSortOption.allCases, id: \.self) { option in
                    Button {
                        UIHaptics.buttonTap()
                        sortOption = option
                    } label: {
                        if sortOption == option {
                            Label(option.rawValue, systemImage: "checkmark")
                        } else {
                            Text(option.rawValue)
                        }
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(sortOption == .all ? AppColors.textSecondary : AppColors.primary)
            }
            .buttonStyle(IconButtonStyle())
        }
    }

    // MARK: - No Results

    private var noResultsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(AppColors.textTertiary)

            Text(searchText.isEmpty ? "No videos match this filter" : "No results for \u{201C}\(searchText)\u{201D}")
                .font(AppTypography.subheadline)
                .foregroundColor(AppColors.textSecondary)
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ForEach(0..<3, id: \.self) { _ in
                SkeletonVideoCard()
                    .padding(.horizontal, 20)
            }
        }
        .shimmer()
    }
    
    // MARK: - Error State

    private func errorStateView(message: String) -> some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(AppColors.backgroundSecondary)
                    .frame(width: 100, height: 100)

                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 40))
                    .foregroundColor(AppColors.textTertiary)
            }

            VStack(spacing: 8) {
                Text("Couldn't Load Videos")
                    .font(AppTypography.title3)
                    .foregroundColor(AppColors.textPrimary)

                Text(message)
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                UIHaptics.buttonTap()
                viewModel.fetchVideos()
            } label: {
                Text("Try Again")
                    .font(AppTypography.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(AppColors.primaryGradient)
                    .cornerRadius(24)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(AppColors.backgroundSecondary)
                    .frame(width: 100, height: 100)
                
                Image(systemName: "play.rectangle.on.rectangle")
                    .font(.system(size: 40))
                    .foregroundColor(AppColors.textTertiary)
            }
            
            VStack(spacing: 8) {
                Text("No Videos Yet")
                    .font(AppTypography.title3)
                    .foregroundColor(AppColors.textPrimary)
                
                Text("Upload your first haptic video\nto see it here")
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private func refreshFeed() async {
        let previousIDs = Set(viewModel.videos.map(\.id))
        await viewModel.fetchVideosAsync()
        let currentIDs = Set(viewModel.videos.map(\.id))
        if !currentIDs.subtracting(previousIDs).isEmpty {
            UIHaptics.success()
        }
    }
}

// MARK: - Modern Video Card

struct ModernVideoCard: View {
    let video: Video
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Thumbnail
                thumbnailSection
                
                // Info Section
                infoSection
            }
            .background(AppColors.backgroundSecondary)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.3), radius: 15, y: 8)
            .scaleEffect(isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
    
    private var thumbnailSection: some View {
        ZStack(alignment: .bottomLeading) {
            // Thumbnail Image
            AsyncImage(url: URL(string: video.thumbnailURL)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                case .failure:
                    thumbnailPlaceholder
                case .empty:
                    thumbnailPlaceholder
                        .shimmer()
                @unknown default:
                    thumbnailPlaceholder
                }
            }
            .frame(height: 200)
            .clipped()
            
            // Gradient Overlay
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Duration & Haptic Badge
            HStack {
                // Haptic Badge
                if video.hasHaptics {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.path")
                            .font(.system(size: 10, weight: .semibold))
                        Text("HAPTIC")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColors.primaryGradient)
                    .cornerRadius(6)
                }

                // Demo Badge
                if video.uploaderID == "demo" {
                    Text("DEMO")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .cornerRadius(6)
                }

                Spacer()
                
                // Duration
                Text(formatDuration(video.duration))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .cornerRadius(6)
            }
            .padding(12)
        }
        .cornerRadius(20, corners: [.topLeft, .topRight])
    }
    
    private var thumbnailPlaceholder: some View {
        Rectangle()
            .fill(AppColors.backgroundTertiary)
            .overlay(
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(AppColors.textTertiary)
            )
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            Text(video.title)
                .font(AppTypography.headline)
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(2)
            
            // Metadata Row
            HStack(spacing: 16) {
                // Uploader
                HStack(spacing: 6) {
                    Circle()
                        .fill(AppColors.primaryGradient)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Text(String(video.uploaderUsername.prefix(1)).uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        )
                    
                    Text(video.uploaderUsername)
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                }
                
                Spacer()

                // Haptics Indicator
                if video.hasHaptics {
                    Image(systemName: "waveform")
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.primary)
                }

                // Views
                HStack(spacing: 4) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 11))
                    Text("\(video.views)")
                }
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textTertiary)
                
                // Date
                Text(formatDate(video.uploadedAt))
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .padding(16)
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        // min(): a slightly-future date renders as "in 0 sec"
        return formatter.localizedString(for: min(date, Date()), relativeTo: Date())
    }
}

// MARK: - Skeleton Video Card

struct SkeletonVideoCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(AppColors.backgroundTertiary)
                .frame(height: 200)
            
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppColors.backgroundTertiary)
                    .frame(height: 20)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppColors.backgroundTertiary)
                    .frame(width: 150, height: 16)
            }
            .padding(16)
        }
        .background(AppColors.backgroundSecondary)
        .cornerRadius(20)
    }
}

#Preview {
    FeedView()
}
