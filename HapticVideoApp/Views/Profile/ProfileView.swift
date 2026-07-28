//
//  ProfileView.swift
//  HapticVideoApp
//
//  Modern 2025 profile UI with glassmorphism and stats cards
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @State private var showSignOutAlert = false
    @State private var animateStats = false
    @State private var showFeedbackForm = false
    @State private var showABTest = false
    @State private var myVideos: [Video] = []
    @State private var selectedVideo: Video?
    @AppStorage("hapticStrength") private var hapticStrength: Double = 1.0

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                AppColors.backgroundDark
                    .ignoresSafeArea()
                
                // Decorative Gradient
                VStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [AppColors.primary.opacity(0.3), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 200
                            )
                        )
                        .frame(width: 400, height: 400)
                        .offset(y: -200)
                        .blur(radius: 60)
                    
                    Spacer()
                }
                .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Profile Header
                        profileHeader
                            .padding(.top, 20)
                        
                        // Stats Cards
                        statsSection
                            .padding(.horizontal, 20)
                        
                        // My Videos
                        myVideosSection
                            .padding(.horizontal, 20)

                        // Account Section
                        accountSection
                            .padding(.horizontal, 20)

                        // Settings Section
                        settingsSection
                            .padding(.horizontal, 20)
                        
                        // Sign Out
                        signOutButton
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        
                        // App Info
                        appInfo
                            .padding(.top, 40)
                        
                        Spacer()
                            .frame(height: 100)
                    }
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Profile")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.textPrimary)
                }
            }
            .toolbarBackground(AppColors.backgroundDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Sign Out", isPresented: $showSignOutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    UIHaptics.selectionChanged()
                    authViewModel.signOut()
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showFeedbackForm) {
            FeedbackFormView()
        }
        .sheet(isPresented: $showABTest) {
            ABTestView()
        }
        .fullScreenCover(item: $selectedVideo, onDismiss: { Task { await loadMyVideos() } }) { video in
            VideoPlayerView(video: video)
        }
        .task {
            await loadMyVideos()
        }
        .refreshable {
            await loadMyVideos()
        }
        .onAppear {
            UIHaptics.prepare()
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                animateStats = true
            }
        }
    }
    
    // MARK: - Profile Header
    
    private var profileHeader: some View {
        VStack(spacing: 16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(AppColors.primaryGradient)
                    .frame(width: 100, height: 100)
                    .shadow(color: AppColors.primary.opacity(0.5), radius: 20, y: 10)
                
                Text(avatarInitials)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            // Name & Username
            VStack(spacing: 4) {
                Text(authViewModel.currentUser?.displayName ?? "User")
                    .font(AppTypography.title2)
                    .foregroundColor(AppColors.textPrimary)
                
                Text("@\(authViewModel.currentUser?.username ?? "username")")
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColors.textSecondary)
            }
            
            // Member Since Badge
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                Text("Member since \(memberSinceText)")
                    .font(AppTypography.caption)
            }
            .foregroundColor(AppColors.textTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppColors.backgroundSecondary)
            .cornerRadius(20)
        }
    }
    
    // MARK: - Stats Section
    
    private var statsSection: some View {
        HStack(spacing: 12) {
            StatCard(
                icon: "play.rectangle.fill",
                value: "\(myVideos.count)",
                label: "Videos",
                color: AppColors.primary,
                animate: animateStats
            )

            StatCard(
                icon: "waveform.path",
                value: "\(myVideos.filter(\.hasHaptics).count)",
                label: "Haptics",
                color: AppColors.info,
                animate: animateStats
            )

            StatCard(
                icon: "eye.fill",
                value: "\(myVideos.reduce(0) { $0 + $1.views })",
                label: "Views",
                color: AppColors.success,
                animate: animateStats
            )
        }
    }
    
    // MARK: - My Videos

    private var myVideosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MY VIDEOS")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(AppColors.textTertiary)

            if myVideos.isEmpty {
                Text("No videos yet — upload one from the Upload tab.")
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(AppColors.backgroundSecondary)
                    .cornerRadius(16)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    ForEach(myVideos) { video in
                        MyVideoCell(video: video)
                            .onTapGesture {
                                UIHaptics.buttonTap()
                                selectedVideo = video
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task { await delete(video) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
    }

    private func loadMyVideos() async {
        guard let userID = authViewModel.currentUser?.id else { return }
        let all = (try? await AppBackend.store.fetchAllVideos()) ?? []
        // Demo seed videos (uploaderID "demo") are not the user's.
        myVideos = all.filter { $0.uploaderID == userID && $0.uploaderID != "demo" }
    }

    private func delete(_ video: Video) async {
        UIHaptics.deleteEvent()
        try? await AppBackend.store.deleteVideo(video)
        myVideos.removeAll { $0.id == video.id }
    }

    // MARK: - Account Section
    
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACCOUNT")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(AppColors.textTertiary)
            
            VStack(spacing: 0) {
                ProfileRow(
                    icon: "envelope.fill",
                    title: "Email",
                    // Local profiles have no email — show a dash, not blank
                    value: (authViewModel.currentUser?.email.isEmpty == false)
                        ? authViewModel.currentUser!.email : "—"
                )
                
                Divider()
                    .background(AppColors.backgroundTertiary)
                
                ProfileRow(
                    icon: "person.fill",
                    title: "Username",
                    value: "@\(authViewModel.currentUser?.username ?? "—")"
                )
                
                Divider()
                    .background(AppColors.backgroundTertiary)
                
                ProfileRow(
                    icon: "person.text.rectangle.fill",
                    title: "Display Name",
                    value: authViewModel.currentUser?.displayName ?? "—"
                )
            }
            .background(AppColors.backgroundSecondary)
            .cornerRadius(16)
        }
    }
    
    // MARK: - Settings Section
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PREFERENCES")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(AppColors.textTertiary)
            
            VStack(spacing: 0) {
                // Haptic Strength
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppColors.textTertiary)
                            .frame(width: 24)

                        Text("Haptic Strength")
                            .font(AppTypography.subheadline)
                            .foregroundColor(AppColors.textPrimary)

                        Spacer()

                        Text(String(format: "%.1fx", hapticStrength))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(AppColors.textSecondary)
                    }

                    Slider(value: $hapticStrength, in: 0.5...1.5, step: 0.1)
                        .tint(AppColors.primary)
                        .onChange(of: hapticStrength) { _, _ in
                            UIHaptics.selectionChanged()
                        }
                }
                .padding(16)

                Divider()
                    .background(AppColors.backgroundTertiary)

                Button {
                    UIHaptics.buttonTap()
                    showABTest = true
                } label: {
                    SettingsRow(
                        icon: "waveform.path.ecg",
                        title: "Haptic Lab",
                        subtitle: "Blind A/B test your haptics"
                    )
                }

                Divider()
                    .background(AppColors.backgroundTertiary)

                Button {
                    UIHaptics.buttonTap()
                    showFeedbackForm = true
                } label: {
                    SettingsRow(icon: "bubble.left.and.bubble.right.fill", title: "Give Feedback")
                }
            }
            .background(AppColors.backgroundSecondary)
            .cornerRadius(16)
        }
    }
    
    // MARK: - Sign Out Button
    
    private var signOutButton: some View {
        Button {
            UIHaptics.buttonTap()
            showSignOutAlert = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Sign Out")
            }
            .font(AppTypography.headline)
            .foregroundColor(AppColors.error)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppColors.error.opacity(0.15))
            )
        }
    }
    
    // MARK: - App Info
    
    private var appInfo: some View {
        VStack(spacing: 8) {
            Text("HapticVideo")
                .font(AppTypography.footnote)
                .foregroundColor(AppColors.textTertiary)
            
            Text("Version 1.0.0")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textTertiary)
        }
    }
    
    // MARK: - Helpers
    
    private var avatarInitials: String {
        guard let name = authViewModel.currentUser?.displayName else { return "?" }
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
    
    private var memberSinceText: String {
        guard let date = authViewModel.currentUser?.createdAt else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    var animate: Bool = false
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.textPrimary)
            
            Text(label)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(AppColors.backgroundSecondary)
        .cornerRadius(16)
        .scaleEffect(animate ? 1 : 0.8)
        .opacity(animate ? 1 : 0)
        .onTapGesture {
            UIHaptics.selectionChanged()
        }
    }
}

// MARK: - Profile Row

struct ProfileRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(AppColors.textTertiary)
                .frame(width: 24)
            
            Text(title)
                .font(AppTypography.subheadline)
                .foregroundColor(AppColors.textSecondary)
            
            Spacer()
            
            Text(value)
                .font(AppTypography.subheadline)
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)
        }
        .padding(16)
    }
}

// MARK: - Settings Row

struct SettingsRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(AppColors.textTertiary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColors.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(16)
    }
}

// MARK: - My Video Cell

struct MyVideoCell: View {
    let video: Video

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: URL(string: video.thumbnailURL)) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        AppColors.backgroundTertiary
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
            }
            .frame(height: 100)
            .frame(maxWidth: .infinity)
            .clipped()
            .cornerRadius(12)

            Text(video.title)
                .font(AppTypography.subheadline)
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)

            HStack(spacing: 4) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 10))
                Text("\(video.views) views")
                    .font(AppTypography.caption)
            }
            .foregroundColor(AppColors.textSecondary)
        }
        .padding(8)
        .background(AppColors.backgroundSecondary)
        .cornerRadius(16)
        .contentShape(Rectangle())
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthenticationViewModel())
}
