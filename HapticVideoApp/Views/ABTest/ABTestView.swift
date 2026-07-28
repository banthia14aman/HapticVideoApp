//
//  ABTestView.swift
//  HapticVideoApp
//
//  Blind A/B preference test: plays a haptic video twice (haptics on/off in
//  random order, tester never told which), asks which version they'd rather
//  watch again, logs the result. The evidence machine for the YC application.
//
//  Blind-proofing: no waveform icons, toggles, or haptic indicators anywhere
//  in the session UI; the haptic toggle is forced internally per version and
//  playback controls are hit-test disabled so the clip can't be scrubbed.
//

import SwiftUI
import AVKit

// MARK: - Entry point

struct ABTestView: View {
    init() {}

    var body: some View {
        NavigationStack {
            ABTestHomeView()
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Home: pick a video

private struct ABTestHomeView: View {
    @StateObject private var store = ABTestStore.shared
    @State private var videos: [Video] = []
    @State private var loaded = false

    var body: some View {
        ZStack {
            AppColors.backgroundDark.ignoresSafeArea()

            if !loaded {
                ProgressView().tint(AppColors.primary)
            } else if videos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 40))
                        .foregroundColor(AppColors.textTertiary)
                    Text("No haptic videos yet")
                        .font(AppTypography.title3)
                        .foregroundColor(AppColors.textPrimary)
                    Text("Upload a video with a haptic track first.")
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pick a clip, then hand the phone to your tester.")
                            .font(AppTypography.subheadline)
                            .foregroundColor(AppColors.textSecondary)
                            .padding(.horizontal)

                        ForEach(videos) { video in
                            NavigationLink {
                                ABTestSessionView(video: video)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(video.title)
                                            .font(AppTypography.headline)
                                            .foregroundColor(AppColors.textPrimary)
                                            .lineLimit(1)
                                        Text("\(Int(video.duration))s clip")
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.footnote)
                                        .foregroundColor(AppColors.textTertiary)
                                }
                                .padding()
                                .background(AppColors.backgroundSecondary)
                                .cornerRadius(12)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle("Blind A/B Test")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ABTestResultsView()
                } label: {
                    Label("Results (\(store.totalTrials))", systemImage: "chart.bar.fill")
                        .font(AppTypography.footnote)
                        .foregroundColor(AppColors.primary)
                }
            }
        }
        .task {
            let all = (try? await AppBackend.store.fetchAllVideos()) ?? []
            videos = all.filter { $0.hasHaptics && $0.hapticsURL != nil }
            loaded = true
        }
    }
}

// MARK: - Session model

@MainActor
private final class ABSessionModel: ObservableObject {
    enum Phase {
        case handoff
        case playing(version: Int)   // 1 = A, 2 = B
        case question
        case reveal(choice: ABTrial.Choice)
    }

    enum Answer { case versionA, versionB, noDifference }

    let video: Video
    /// Randomized once per trial; never surfaced to the tester.
    let hapticsFirst = Bool.random()

    @Published var phase: Phase = .handoff
    @Published var player: AVPlayer?
    @Published var clipEnded = false
    @Published var loadError: String?

    private var events: [HapticEvent] = []
    private var endObserver: Any?
    private let haptics = HapticService.shared

    init(video: Video) {
        self.video = video
    }

    func loadHaptics() async {
        guard events.isEmpty else { return }
        guard let path = video.hapticsURL, let url = URL(string: path) else {
            loadError = "This video has no haptic track."
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let pattern = try decoder.decode(HapticPattern.self, from: data)
            // Don't let haptics run past the clip.
            events = pattern.events.filter { $0.time + $0.duration <= video.duration }
            if events.isEmpty { loadError = "This video's haptic track is empty." }
        } catch {
            loadError = "Couldn't load haptics: \(error.localizedDescription)"
        }
    }

    /// The haptic toggle, forced internally — blind by construction.
    private func hapticsOn(forVersion version: Int) -> Bool {
        (version == 1) == hapticsFirst
    }

    func startVersion(_ version: Int) {
        stopPlayback()
        clipEnded = false
        phase = .playing(version: version)

        guard let url = URL(string: video.videoURL) else {
            loadError = "Couldn't open this video file."
            return
        }
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.haptics.stopAdvancedPlayer()
                self.clipEnded = true
            }
        }

        let withHaptics = hapticsOn(forVersion: version)
        if withHaptics {
            _ = haptics.loadPattern(events)
        } else {
            haptics.stopAdvancedPlayer()
        }
        p.play()
        if withHaptics {
            haptics.seekAdvancedPlayer(to: 0)
            haptics.startAdvancedPlayer()
        }
    }

    /// "Next" after a clip finishes: A → B, B → the question.
    func advance() {
        switch phase {
        case .playing(version: 1):
            startVersion(2)
        case .playing(version: 2):
            stopPlayback()
            phase = .question
        default:
            break
        }
    }

    func submit(_ answer: Answer) {
        let choice: ABTrial.Choice
        switch answer {
        case .versionA:     choice = hapticsFirst ? .hapticsOn : .hapticsOff
        case .versionB:     choice = hapticsFirst ? .hapticsOff : .hapticsOn
        case .noDifference: choice = .noDifference
        }
        ABTestStore.shared.record(videoID: video.id,
                                  videoTitle: video.title,
                                  hapticsWasFirst: hapticsFirst,
                                  choice: choice)
        phase = .reveal(choice: choice)
    }

    func stopPlayback() {
        haptics.stopAdvancedPlayer()
        player?.pause()
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
        player = nil
    }
}

// MARK: - Session view

private struct ABTestSessionView: View {
    @StateObject private var model: ABSessionModel
    @Environment(\.dismiss) private var dismiss

    init(video: Video) {
        _model = StateObject(wrappedValue: ABSessionModel(video: video))
    }

    var body: some View {
        ZStack {
            AppColors.backgroundDark.ignoresSafeArea()

            if let error = model.loadError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundColor(AppColors.warning)
                    Text(error)
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button("Back") { dismiss() }
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primary)
                }
            } else {
                switch model.phase {
                case .handoff:
                    handoffView
                case .playing(let version):
                    playingView(version: version)
                case .question:
                    questionView
                case .reveal(let choice):
                    revealView(choice: choice)
                }
            }
        }
        .navigationBarBackButtonHidden(hideChrome)
        .toolbar(hideChrome ? .hidden : .visible, for: .tabBar)
        .task { await model.loadHaptics() }
        .onDisappear { model.stopPlayback() }
    }

    /// Hide nav/tab chrome while the tester holds the phone.
    private var hideChrome: Bool {
        switch model.phase {
        case .handoff: return false
        default: return true
        }
    }

    // MARK: Handoff

    private var handoffView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 56))
                .foregroundColor(AppColors.primary)
            Text("Hand the phone to your tester")
                .font(AppTypography.title2)
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)
            Text("They'll watch the same clip twice — Version A, then Version B — and pick the one they'd rather watch again. Hold the phone in your hand, not on a table.")
                .font(AppTypography.body)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            bigButton("Start Version A") {
                model.startVersion(1)
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: Playing

    private func playingView(version: Int) -> some View {
        ZStack {
            if let player = model.player {
                VideoPlayer(player: player)
                    .allowsHitTesting(false)   // no scrubbing, no control chrome interaction
                    .ignoresSafeArea()
            }

            VStack {
                Text("Version \(version == 1 ? "A" : "B")")
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 16)
                Spacer()
                if model.clipEnded {
                    bigButton(version == 1 ? "Next: Version B" : "Answer") {
                        model.advance()
                    }
                    .padding(.bottom, 48)
                }
            }
        }
    }

    // MARK: Question

    private var questionView: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Which version would you rather watch again?")
                .font(AppTypography.title2)
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            VStack(spacing: 12) {
                bigButton("Version A") { model.submit(.versionA) }
                bigButton("Version B") { model.submit(.versionB) }
                Button("No difference") { model.submit(.noDifference) }
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.top, 8)
            }
            .padding(.bottom, 48)
        }
    }

    // MARK: Reveal

    private func revealView(choice: ABTrial.Choice) -> some View {
        let hapticVersion = model.hapticsFirst ? "A" : "B"
        let pickedHaptics = choice == .hapticsOn

        return VStack(spacing: 24) {
            Spacer()
            Image(systemName: pickedHaptics ? "checkmark.seal.fill" : "seal")
                .font(.system(size: 56))
                .foregroundColor(pickedHaptics ? AppColors.success : AppColors.textTertiary)
            Text("Version \(hapticVersion) had haptics ON")
                .font(AppTypography.title2)
                .foregroundColor(AppColors.textPrimary)
            Text(revealLine(choice: choice))
                .font(AppTypography.body)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("Result recorded.")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textTertiary)
            Spacer()
            bigButton("Done") { dismiss() }
                .padding(.bottom, 32)
        }
    }

    private func revealLine(choice: ABTrial.Choice) -> String {
        switch choice {
        case .hapticsOn:    return "Your tester preferred the haptic version."
        case .hapticsOff:   return "Your tester preferred the version without haptics."
        case .noDifference: return "Your tester felt no difference."
        }
    }

    // MARK: Shared button

    private func bigButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AppColors.primaryGradient)
                .cornerRadius(14)
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Results

private struct ABTestResultsView: View {
    @StateObject private var store = ABTestStore.shared
    @State private var showResetConfirm = false

    var body: some View {
        ZStack {
            AppColors.backgroundDark.ignoresSafeArea()

            if store.totalTrials == 0 {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 40))
                        .foregroundColor(AppColors.textTertiary)
                    Text("No trials yet")
                        .font(AppTypography.title3)
                        .foregroundColor(AppColors.textPrimary)
                    Text("Run a blind test to start collecting data.")
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                }
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        headline
                        perVideoSection
                        ShareLink(item: store.shareSummary) {
                            Label("Share results", systemImage: "square.and.arrow.up")
                                .font(AppTypography.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppColors.primaryGradient)
                                .cornerRadius(14)
                        }
                        Button(role: .destructive) {
                            showResetConfirm = true
                        } label: {
                            Text("Reset data")
                                .font(AppTypography.subheadline)
                                .foregroundColor(AppColors.error)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Results")
        .confirmationDialog("Delete all \(store.totalTrials) trials?",
                            isPresented: $showResetConfirm,
                            titleVisibility: .visible) {
            Button("Delete all trials", role: .destructive) { store.reset() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var headline: some View {
        VStack(spacing: 8) {
            Text("\(store.preferredHaptics) of \(store.decidedTrials)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.primary)
            Text("preferred haptics ON")
                .font(AppTypography.title3)
                .foregroundColor(AppColors.textPrimary)
            if let pct = store.percentPreferHaptics {
                Text(String(format: "%.0f%% of testers who felt a difference • %d trials total • %d no difference",
                            pct, store.totalTrials, store.noDifferenceCount))
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(AppColors.backgroundSecondary)
        .cornerRadius(16)
    }

    private var perVideoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("By video")
                .font(AppTypography.headline)
                .foregroundColor(AppColors.textPrimary)

            ForEach(store.perVideoStats) { stats in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(stats.title)
                            .font(AppTypography.subheadline)
                            .foregroundColor(AppColors.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(stats.hapticsOn)/\(stats.decided)")
                            .font(AppTypography.mono)
                            .foregroundColor(AppColors.textSecondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(AppColors.backgroundTertiary)
                            Capsule()
                                .fill(AppColors.primary)
                                .frame(width: geo.size.width * stats.preferenceFraction)
                        }
                    }
                    .frame(height: 8)
                    if stats.noDifference > 0 {
                        Text("\(stats.noDifference) no difference")
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
            }
        }
        .padding()
        .background(AppColors.backgroundSecondary)
        .cornerRadius(16)
    }
}
