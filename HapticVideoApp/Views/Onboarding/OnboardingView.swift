//
//  OnboardingView.swift
//  HapticVideoApp
//
//  3-page first-run experience: feel the product in 20 seconds.
//

import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var page = 0

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppColors.backgroundDark, AppColors.backgroundPrimary, Color(hex: "1A0A10")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            TabView(selection: $page) {
                WaveformPage().tag(0)
                HeartbeatPage().tag(1)
                CreatePage(onComplete: onComplete).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: page)

            VStack {
                HStack {
                    Spacer()
                    if page < 2 {
                        Button("Skip") { onComplete() }
                            .font(AppTypography.subheadline)
                            .foregroundColor(AppColors.textSecondary)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                    }
                }
                Spacer()
                // Progress dots
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? AppColors.primary : AppColors.glassBorder)
                            .frame(width: i == page ? 24 : 8, height: 8)
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: page)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Page 1: Silent Video

private struct WaveformPage: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            AnimatedWaveform(excited: pulse)
                .frame(height: 140)
                .padding(.horizontal, 40)
                .scaleEffect(pulse ? 1.06 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: pulse)

            VStack(spacing: 12) {
                Text("Video has been silent\nto your hands")
                    .font(AppTypography.title)
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Tap anywhere to feel your first frame.")
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { playSample() }
    }

    private func playSample() {
        // A quick crack, a body thump, and a short fading rumble.
        HapticService.shared.playEvent(
            HapticEvent(time: 0, intensity: 1.0, sharpness: 0.9, duration: 0, type: .transient)
        )
        Task {
            try? await Task.sleep(nanoseconds: 90_000_000)
            HapticService.shared.playEvent(
                HapticEvent(time: 0, intensity: 0.8, sharpness: 0.3, duration: 0, type: .impact)
            )
            try? await Task.sleep(nanoseconds: 120_000_000)
            HapticService.shared.playEvent(
                HapticEvent(time: 0, intensity: 0.5, sharpness: 0.15, duration: 0.35, type: .continuous)
            )
        }
        pulse = true
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            pulse = false
        }
    }
}

/// Idle-breathing waveform bars; jump on `excited`.
private struct AnimatedWaveform: View {
    var excited: Bool
    private let barCount = 27

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 5) {
                ForEach(0..<barCount, id: \.self) { i in
                    let base = sin(t * 2.2 + Double(i) * 0.55) * 0.5 + 0.5
                    let envelope = sin(Double(i) / Double(barCount - 1) * .pi) // taller in middle
                    let h = 12 + base * envelope * (excited ? 120 : 70)
                    Capsule()
                        .fill(AppColors.primaryGradient)
                        .frame(width: 5, height: h)
                        .opacity(0.5 + base * 0.5)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Page 2: Heartbeat (press and hold)

private struct HeartbeatPage: View {
    @State private var isHolding = false
    @State private var beatTask: Task<Void, Never>?
    @State private var beatScale: CGFloat = 1

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Text("Feel the difference")
                    .font(AppTypography.title)
                    .foregroundColor(AppColors.textPrimary)

                Text("Press and hold. That's a heartbeat.")
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            ZStack {
                // Glow rings
                Circle()
                    .fill(AppColors.primary.opacity(isHolding ? 0.25 : 0.08))
                    .frame(width: 260, height: 260)
                    .scaleEffect(beatScale * 1.05)
                Circle()
                    .fill(AppColors.primaryGradient)
                    .frame(width: 180, height: 180)
                    .shadow(color: AppColors.primary.opacity(isHolding ? 0.7 : 0.3), radius: isHolding ? 40 : 16)
                    .scaleEffect(beatScale)

                Image(systemName: "heart.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.white)
                    .scaleEffect(beatScale)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: beatScale)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isHolding { startHeartbeat() }
                    }
                    .onEnded { _ in stopHeartbeat() }
            )

            Text(isHolding ? "Don't let go." : "Hold me")
                .font(AppTypography.headline)
                .foregroundColor(isHolding ? AppColors.primary : AppColors.textSecondary)
                .animation(.easeInOut(duration: 0.2), value: isHolding)

            Spacer()
            Spacer()
        }
        .onDisappear { stopHeartbeat() }
    }

    private func startHeartbeat() {
        isHolding = true
        beatTask = Task {
            // Lub-dub, quiet diastole, repeat — slightly quickening.
            var interval: UInt64 = 650_000_000
            while !Task.isCancelled {
                // LUB — deep, round thump
                HapticService.shared.playEvent(
                    HapticEvent(time: 0, intensity: 1.0, sharpness: 0.25, duration: 0, type: .transient)
                )
                bump(1.12)
                try? await Task.sleep(nanoseconds: 110_000_000)
                if Task.isCancelled { break }

                // dub — softer, slightly sharper echo
                HapticService.shared.playEvent(
                    HapticEvent(time: 0, intensity: 0.65, sharpness: 0.4, duration: 0, type: .transient)
                )
                bump(1.06)
                try? await Task.sleep(nanoseconds: 70_000_000)
                if Task.isCancelled { break }

                // faint after-resonance
                HapticService.shared.playEvent(
                    HapticEvent(time: 0, intensity: 0.25, sharpness: 0.1, duration: 0.12, type: .continuous)
                )

                try? await Task.sleep(nanoseconds: interval)
                // Excitement: heart rate creeps up the longer you hold.
                if interval > 400_000_000 { interval -= 25_000_000 }
            }
        }
    }

    private func stopHeartbeat() {
        beatTask?.cancel()
        beatTask = nil
        isHolding = false
        beatScale = 1
    }

    private func bump(_ scale: CGFloat) {
        beatScale = scale
        Task {
            try? await Task.sleep(nanoseconds: 90_000_000)
            beatScale = 1
        }
    }
}

// MARK: - Page 3: Create

private struct CreatePage: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 72))
                .foregroundStyle(AppColors.primaryGradient)
                .shadow(color: AppColors.primary.opacity(0.5), radius: 24)

            VStack(spacing: 12) {
                Text("Create your own")
                    .font(AppTypography.title)
                    .foregroundColor(AppColors.textPrimary)

                Text("AI turns any video's sound into touch — then fine-tune every hit in the editor.")
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            Button("Get Started") { onComplete() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 64)
        }
    }
}
