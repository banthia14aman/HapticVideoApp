//
//  LivePerformanceView.swift
//  HapticVideoApp
//
//  Record haptics by performing them live while the video plays:
//  tap the pads for transient hits, press-and-hold for continuous rumbles.
//

import SwiftUI
import AVKit

// MARK: - Live Performance View

struct LivePerformanceView: View {

    let videoURL: URL
    let videoDuration: Double
    let onSave: ([HapticEvent]) -> Void

    init(videoURL: URL, videoDuration: Double, onSave: @escaping ([HapticEvent]) -> Void) {
        self.videoURL = videoURL
        self.videoDuration = videoDuration
        self.onSave = onSave
        _player = State(initialValue: AVPlayer(url: videoURL))
    }

    // MARK: State

    private enum Phase { case countdown, recording, paused, review }

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    @State private var phase: Phase = .countdown
    @State private var countdown: Int = 3
    @State private var countdownGeneration: Int = 0
    @State private var events: [HapticEvent] = []
    @State private var currentTime: Double = 0
    @State private var timeObserver: Any?

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            videoSection
            progressStrip
            transportBar
            padSection
        }
        .background(EditorColors.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            UIHaptics.prepare()
            attachTimeObserver()
            startCountdown()
        }
        .onDisappear {
            player.pause()
            if let timeObserver { player.removeTimeObserver(timeObserver) }
            timeObserver = nil
            HapticService.shared.stopAllHaptics()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem)) { _ in
            enterReview()
        }
        .overlay { overlays }
    }

    // MARK: Video

    private var videoSection: some View {
        VideoPlayer(player: player)
            .allowsHitTesting(false)   // no system controls; transport bar drives it
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
    }

    // MARK: Progress strip (slim, with floating event markers)

    private var progressStrip: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(EditorColors.trackBackground)
                Capsule()
                    .fill(EditorColors.accentMuted)
                    .frame(width: width * progress)

                ForEach(events) { event in
                    let x = videoDuration > 0 ? CGFloat(event.time / videoDuration) * width : 0
                    if event.type == .continuous {
                        Capsule()
                            .fill(EditorColors.color(for: event.type).opacity(0.85))
                            .frame(width: max(4, CGFloat(event.duration / max(videoDuration, 0.01)) * width),
                                   height: 6)
                            .offset(x: x)
                    } else {
                        Circle()
                            .fill(EditorColors.color(for: event.type))
                            .frame(width: 6, height: 6)
                            .offset(x: x - 3)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                // Playhead tick
                Rectangle()
                    .fill(EditorColors.playhead)
                    .frame(width: 2, height: 12)
                    .offset(x: width * progress - 1)
            }
        }
        .frame(height: 12)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: events.count)
    }

    private var progress: CGFloat {
        videoDuration > 0 ? CGFloat(min(max(currentTime / videoDuration, 0), 1)) : 0
    }

    // MARK: Transport

    private var transportBar: some View {
        HStack(spacing: 32) {
            Button(action: restart) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 18, weight: .semibold))
            }

            Button(action: togglePlayPause) {
                Image(systemName: phase == .recording ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .semibold))
            }
            .disabled(phase == .countdown || phase == .review)

            Spacer()

            Text("\(events.count) events")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(EditorColors.textSecondary)

            Button("Done") { enterReview() }
                .font(.system(size: 15, weight: .semibold))
                .disabled(phase == .review)
        }
        .foregroundColor(EditorColors.textPrimary)
        .padding(.horizontal, 20)
        .frame(height: EditorDimensions.transportHeight)
        .background(EditorColors.panel)
    }

    // MARK: Pads

    private var padSection: some View {
        HStack(spacing: 14) {
            PerformancePad(
                label: "Soft",
                color: EditorColors.transient,
                tapType: .transient,
                tapIntensity: 0.6,
                holdIntensity: 0.5,
                sharpness: 0.4,
                enabled: phase == .recording,
                now: { player.currentTime().seconds },
                record: record
            )
            PerformancePad(
                label: "Hard",
                color: EditorColors.impact,
                tapType: .impact,
                tapIntensity: 0.95,
                holdIntensity: 0.8,
                sharpness: 0.7,
                enabled: phase == .recording,
                now: { player.currentTime().seconds },
                record: record
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 20)
        .frame(height: 220)
        .background(EditorColors.panel)
    }

    // MARK: Overlays

    @ViewBuilder
    private var overlays: some View {
        if phase == .countdown {
            ZStack {
                Color.black.opacity(0.6).ignoresSafeArea()
                Text("\(countdown)")
                    .font(.system(size: 110, weight: .heavy, design: .rounded))
                    .foregroundColor(EditorColors.accent)
                    .id(countdown)   // re-trigger transition each tick
                    .transition(.scale(scale: 1.6).combined(with: .opacity))
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: countdown)
        } else if phase == .review {
            reviewOverlay
        }
    }

    private var reviewOverlay: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 22) {
                Image(systemName: "waveform.path")
                    .font(.system(size: 40))
                    .foregroundColor(EditorColors.accent)
                Text("\(events.count) event\(events.count == 1 ? "" : "s") recorded")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(EditorColors.textPrimary)

                Button {
                    UIHaptics.success()
                    onSave(events.sorted { $0.time < $1.time })
                    dismiss()
                } label: {
                    Text("Save Performance")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(EditorColors.accent)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                .disabled(events.isEmpty)
                .opacity(events.isEmpty ? 0.4 : 1)

                HStack(spacing: 28) {
                    Button("Retry") {
                        UIHaptics.buttonTap()
                        restart()
                    }
                    .foregroundColor(EditorColors.textPrimary)

                    Button("Discard") {
                        UIHaptics.deleteEvent()
                        dismiss()
                    }
                    .foregroundColor(EditorColors.playhead)
                }
                .font(.system(size: 15, weight: .medium))
            }
            .padding(28)
            .frame(maxWidth: 320)
            .background(EditorColors.panel)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: Actions

    private func record(_ event: HapticEvent) {
        guard phase == .recording else { return }
        events.append(event)
    }

    private func attachTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { time in
            currentTime = time.seconds
        }
    }

    private func startCountdown() {
        phase = .countdown
        countdownGeneration += 1
        let generation = countdownGeneration
        Task { @MainActor in
            for tick in stride(from: 3, through: 1, by: -1) {
                guard generation == countdownGeneration, phase == .countdown else { return }
                countdown = tick
                UIHaptics.buttonTapMedium()
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
            guard generation == countdownGeneration, phase == .countdown else { return }
            phase = .recording
            UIHaptics.play()
            player.play()
        }
    }

    private func togglePlayPause() {
        if phase == .recording {
            player.pause()
            phase = .paused
            UIHaptics.pause()
        } else if phase == .paused {
            player.play()
            phase = .recording
            UIHaptics.play()
        }
    }

    private func restart() {
        player.pause()
        HapticService.shared.stopAllHaptics()
        events.removeAll()
        currentTime = 0
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        startCountdown()
    }

    private func enterReview() {
        guard phase != .review else { return }
        player.pause()
        HapticService.shared.stopAllHaptics()
        phase = .review
        UIHaptics.success()
    }
}

// MARK: - Performance Pad

/// One big glowing pad. Tap → transient/impact hit; press-and-hold past
/// `holdThreshold` → continuous event lasting the hold.
private struct PerformancePad: View {

    let label: String
    let color: Color
    let tapType: HapticEventType
    let tapIntensity: Float
    let holdIntensity: Float
    let sharpness: Float
    let enabled: Bool
    let now: () -> Double
    let record: (HapticEvent) -> Void

    private static let holdThreshold: TimeInterval = 0.25

    @State private var isPressed = false
    @State private var pressWallTime: Date?
    @State private var pressVideoTime: Double = 0
    @State private var holdWork: DispatchWorkItem?
    @State private var rings: [UUID] = []

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [
                            EditorColors.surfaceElevated,
                            isPressed ? color.opacity(0.35) : EditorColors.trackBackground
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(isPressed ? color : color.opacity(0.35),
                                      lineWidth: isPressed ? 3 : 1.5)
                )
                .shadow(color: color.opacity(isPressed ? 0.7 : 0.15),
                        radius: isPressed ? 24 : 8)

            ForEach(rings, id: \.self) { _ in
                TapRing(color: color)
            }

            VStack(spacing: 8) {
                Image(systemName: EditorColors.icon(for: tapType))
                    .font(.system(size: 30))
                Text(label)
                    .font(.system(size: 17, weight: .bold))
                Text("tap · hold")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(EditorColors.textTertiary)
            }
            .foregroundColor(isPressed ? color : EditorColors.textSecondary)
        }
        .scaleEffect(isPressed ? 0.94 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.55), value: isPressed)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(enabled ? 1 : 0.45)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if pressWallTime == nil { beginPress() } }
                .onEnded { _ in endPress() }
        )
        .disabled(!enabled)
    }

    // MARK: Press handling

    private func beginPress() {
        guard enabled else { return }
        isPressed = true
        pressWallTime = Date()
        pressVideoTime = now()

        // Only start the live continuous buzz once the press outlives a tap.
        let work = DispatchWorkItem {
            // ponytail: 30s cap on the live buzz; release stops it anyway.
            HapticService.shared.playEvent(
                HapticEvent(time: 0, intensity: holdIntensity, sharpness: sharpness,
                            duration: 30, type: .continuous)
            )
        }
        holdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdThreshold, execute: work)
    }

    private func endPress() {
        guard let start = pressWallTime else { return }
        isPressed = false
        pressWallTime = nil
        holdWork?.cancel()
        holdWork = nil

        let hold = Date().timeIntervalSince(start)
        if hold < Self.holdThreshold {
            let event = HapticEvent(time: pressVideoTime, intensity: tapIntensity,
                                    sharpness: sharpness, duration: 0, type: tapType)
            var feedback = event
            feedback.time = 0
            HapticService.shared.playEvent(feedback)
            spawnRing()
            record(event)
        } else {
            HapticService.shared.stopAllHaptics()   // ends the live buzz
            record(HapticEvent(time: pressVideoTime, intensity: holdIntensity,
                               sharpness: sharpness, duration: hold, type: .continuous))
        }
    }

    private func spawnRing() {
        let id = UUID()
        rings.append(id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            rings.removeAll { $0 == id }
        }
    }
}

// MARK: - Tap Ring

/// Quick expanding ring fired on each tap.
private struct TapRing: View {
    let color: Color
    @State private var animate = false

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 3)
            .frame(width: 70, height: 70)
            .scaleEffect(animate ? 1.9 : 0.5)
            .opacity(animate ? 0 : 0.9)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) { animate = true }
            }
    }
}
