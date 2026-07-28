//
//  HapticPresetsSheet.swift
//  HapticVideoApp
//
//  Designed haptic effects library. Preset event times are relative (0-based)
//  and offset by `currentTime` on insert.
//

import SwiftUI

// MARK: - Preset Model

private struct HapticPreset: Identifiable {
    let name: String
    let icon: String
    let category: String
    let events: [HapticEvent]
    var id: String { name }

    /// Total span of the preset, for glyph scaling.
    var span: Double {
        events.map { $0.time + max($0.duration, 0.05) }.max() ?? 1
    }
}

// MARK: - Preset Library

private let presetLibrary: [HapticPreset] = [

    // ── Rhythm ──────────────────────────────────────────────

    HapticPreset(name: "Heartbeat", icon: "heart.fill", category: "Rhythm", events: [
        // lub-dub ×2: heavy low thump, softer echo 180ms later
        HapticEvent(time: 0.00, intensity: 0.95, sharpness: 0.12, duration: 0, type: .impact),
        HapticEvent(time: 0.18, intensity: 0.55, sharpness: 0.08, duration: 0, type: .transient),
        HapticEvent(time: 0.80, intensity: 0.95, sharpness: 0.12, duration: 0, type: .impact),
        HapticEvent(time: 0.98, intensity: 0.55, sharpness: 0.08, duration: 0, type: .transient),
    ]),

    HapticPreset(name: "Drumroll", icon: "metronome.fill", category: "Rhythm", events:
        // Accelerating ticks (interval 160ms -> 50ms, swelling) → crash + rumble tail
        zip([0.00, 0.16, 0.31, 0.45, 0.58, 0.70, 0.81, 0.91, 1.00, 1.08, 1.15, 1.21, 1.26, 1.31],
            stride(from: 0.35, through: 0.74, by: 0.03))
            .map { HapticEvent(time: $0, intensity: Float($1), sharpness: 0.5, duration: 0, type: .transient) }
        + [
            HapticEvent(time: 1.40, intensity: 1.0, sharpness: 0.75, duration: 0, type: .impact),
            HapticEvent(time: 1.42, intensity: 1.0, sharpness: 0.15, duration: 0.5, type: .continuous, intensityCurve: [
                HapticCurvePoint(time: 0.0, value: 0.8),
                HapticCurvePoint(time: 0.2, value: 0.4),
                HapticCurvePoint(time: 0.5, value: 0.0),
            ]),
        ]),

    // ── Impact ──────────────────────────────────────────────

    HapticPreset(name: "Explosion", icon: "burst.fill", category: "Impact", events: [
        // Sharp crack, then a long low decaying rumble
        HapticEvent(time: 0.00, intensity: 1.0, sharpness: 1.0, duration: 0, type: .transient),
        HapticEvent(time: 0.02, intensity: 1.0, sharpness: 0.08, duration: 1.4, type: .continuous, intensityCurve: [
            HapticCurvePoint(time: 0.00, value: 1.0),
            HapticCurvePoint(time: 0.15, value: 0.75),
            HapticCurvePoint(time: 0.50, value: 0.40),
            HapticCurvePoint(time: 1.00, value: 0.15),
            HapticCurvePoint(time: 1.40, value: 0.0),
        ]),
    ]),

    HapticPreset(name: "Punch", icon: "figure.boxing", category: "Impact", events: [
        // One hard hit + tiny fleshy tail
        HapticEvent(time: 0.00, intensity: 1.0, sharpness: 0.8, duration: 0, type: .impact),
        HapticEvent(time: 0.03, intensity: 0.6, sharpness: 0.15, duration: 0.2, type: .continuous, intensityCurve: [
            HapticCurvePoint(time: 0.0, value: 1.0),
            HapticCurvePoint(time: 0.2, value: 0.0),
        ]),
    ]),

    HapticPreset(name: "Earthquake", icon: "waveform.path.ecg", category: "Impact", events: [
        // Low sustained rumble with irregular wobble
        HapticEvent(time: 0.0, intensity: 1.0, sharpness: 0.05, duration: 2.0, type: .continuous, intensityCurve: [
            HapticCurvePoint(time: 0.00, value: 0.30),
            HapticCurvePoint(time: 0.25, value: 0.90),
            HapticCurvePoint(time: 0.50, value: 0.50),
            HapticCurvePoint(time: 0.80, value: 1.00),
            HapticCurvePoint(time: 1.10, value: 0.60),
            HapticCurvePoint(time: 1.40, value: 0.95),
            HapticCurvePoint(time: 1.70, value: 0.40),
            HapticCurvePoint(time: 2.00, value: 0.10),
        ]),
        HapticEvent(time: 0.80, intensity: 0.8, sharpness: 0.1, duration: 0, type: .impact),
        HapticEvent(time: 1.40, intensity: 0.7, sharpness: 0.1, duration: 0, type: .impact),
    ]),

    // ── Mechanical ──────────────────────────────────────────

    HapticPreset(name: "Engine Rev", icon: "engine.combustion.fill", category: "Mechanical", events: [
        // Rising throttle then sputtering back off
        HapticEvent(time: 0.0, intensity: 1.0, sharpness: 0.3, duration: 1.5, type: .continuous, intensityCurve: [
            HapticCurvePoint(time: 0.00, value: 0.20),
            HapticCurvePoint(time: 0.50, value: 0.40),
            HapticCurvePoint(time: 1.00, value: 0.70),
            HapticCurvePoint(time: 1.40, value: 1.00),
            HapticCurvePoint(time: 1.50, value: 0.85),
        ]),
        HapticEvent(time: 1.55, intensity: 0.5, sharpness: 0.6, duration: 0, type: .transient),
        HapticEvent(time: 1.66, intensity: 0.4, sharpness: 0.6, duration: 0, type: .transient),
        HapticEvent(time: 1.78, intensity: 0.3, sharpness: 0.55, duration: 0, type: .transient),
    ]),

    HapticPreset(name: "Laser", icon: "bolt.horizontal.fill", category: "Mechanical", events:
        // Sharp ascending ticks, pitch and punch rising together
        (0..<5).map { i in
            HapticEvent(time: Double(i) * 0.08,
                        intensity: 0.35 + Float(i) * 0.16,
                        sharpness: 0.6 + Float(i) * 0.1,
                        duration: 0, type: .transient)
        }),

    // ── Ambient ─────────────────────────────────────────────

    HapticPreset(name: "Rain", icon: "cloud.rain.fill", category: "Ambient", events:
        // Soft scattered droplets (fixed pseudo-random pattern so it inserts deterministically)
        zip([0.00, 0.13, 0.31, 0.42, 0.60, 0.77, 0.89, 1.08, 1.24, 1.41, 1.55, 1.72, 1.90],
            [0.25, 0.35, 0.20, 0.40, 0.28, 0.22, 0.38, 0.26, 0.33, 0.21, 0.36, 0.24, 0.30])
            .enumerated()
            .map { i, e in
                HapticEvent(time: e.0, intensity: Float(e.1),
                            sharpness: 0.5 + Float(i % 3) * 0.1,
                            duration: 0, type: .transient)
            }),

    // ── UI ──────────────────────────────────────────────────

    HapticPreset(name: "Notification", icon: "bell.badge.fill", category: "UI", events: [
        // Elegant double-tap: soft then confident
        HapticEvent(time: 0.00, intensity: 0.6, sharpness: 0.45, duration: 0, type: .transient),
        HapticEvent(time: 0.12, intensity: 1.0, sharpness: 0.65, duration: 0, type: .transient),
    ]),

    HapticPreset(name: "Success", icon: "checkmark.seal.fill", category: "UI", events: [
        // Rising triad
        HapticEvent(time: 0.00, intensity: 0.5, sharpness: 0.40, duration: 0, type: .transient),
        HapticEvent(time: 0.14, intensity: 0.7, sharpness: 0.60, duration: 0, type: .transient),
        HapticEvent(time: 0.28, intensity: 1.0, sharpness: 0.80, duration: 0, type: .transient),
    ]),
]

private let categoryOrder = ["Rhythm", "Impact", "Mechanical", "Ambient", "UI"]

// MARK: - Sheet

struct HapticPresetsSheet: View {
    let currentTime: Double
    let onInsert: ([HapticEvent]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var previewTask: Task<Void, Never>?
    @State private var previewingID: String?

    init(currentTime: Double, onInsert: @escaping ([HapticEvent]) -> Void) {
        self.currentTime = currentTime
        self.onInsert = onInsert
    }

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(categoryOrder, id: \.self) { category in
                        let presets = presetLibrary.filter { $0.category == category }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(category.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(1.2)
                                .foregroundColor(EditorColors.textTertiary)
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(presets) { preset in
                                    PresetCard(preset: preset,
                                               isPreviewing: previewingID == preset.id,
                                               onPreview: { preview(preset) },
                                               onInsert: { insert(preset) })
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(EditorColors.background)
            .navigationTitle("Haptic Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(EditorColors.textSecondary)
                }
            }
            .toolbarBackground(EditorColors.panel, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onDisappear { previewTask?.cancel() }
    }

    // MARK: Preview

    private func preview(_ preset: HapticPreset) {
        previewTask?.cancel()
        previewingID = preset.id
        UIHaptics.buttonTap()
        let events = preset.events.sorted { $0.time < $1.time }
        previewTask = Task {
            let start = Date()
            for event in events {
                let delay = event.time - Date().timeIntervalSince(start)
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                if Task.isCancelled { return }
                // Fresh ID each preview — HapticService dedupes by event.id.
                var copy = event
                copy.id = UUID()
                HapticService.shared.playEvent(copy)
            }
            // Clear the highlight once the tail finishes.
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled {
                await MainActor.run { if previewingID == preset.id { previewingID = nil } }
            }
        }
    }

    // MARK: Insert

    private func insert(_ preset: HapticPreset) {
        previewTask?.cancel()
        let offset = preset.events.map { event -> HapticEvent in
            var e = event
            e.id = UUID()
            e.time = event.time + currentTime
            return e
        }
        UIHaptics.addEvent()
        onInsert(offset)
        dismiss()
    }
}

// MARK: - Preset Card

private struct PresetCard: View {
    let preset: HapticPreset
    let isPreviewing: Bool
    let onPreview: () -> Void
    let onInsert: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PresetGlyph(preset: preset)
                .frame(height: 44)
                .frame(maxWidth: .infinity)
                .background(EditorColors.trackBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 6) {
                Image(systemName: preset.icon)
                    .font(.system(size: 12))
                    .foregroundColor(EditorColors.accent)
                Text(preset.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(EditorColors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Button(action: onInsert) {
                Text("Insert")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(EditorColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(EditorColors.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isPreviewing ? EditorColors.accent : EditorColors.divider, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onPreview)
    }
}

// MARK: - Glyph (mini event visualization)

private struct PresetGlyph: View {
    let preset: HapticPreset

    var body: some View {
        Canvas { context, size in
            let span = preset.span
            let inset: CGFloat = 4
            let w = size.width - inset * 2
            let h = size.height - inset * 2

            func x(_ t: Double) -> CGFloat { inset + w * CGFloat(t / span) }
            func y(_ v: Float) -> CGFloat { inset + h * (1 - CGFloat(v)) }

            for event in preset.events {
                let color = EditorColors.color(for: event.type)
                if event.type == .continuous {
                    // Filled envelope from baseline
                    let points: [(Double, Float)] = (event.intensityCurve?.isEmpty == false)
                        ? event.intensityCurve!.map { (event.time + $0.time, $0.value * event.intensity) }
                        : [(event.time, event.intensity), (event.time + event.duration, event.intensity)]
                    var path = Path()
                    path.move(to: CGPoint(x: x(points[0].0), y: inset + h))
                    for p in points {
                        path.addLine(to: CGPoint(x: x(p.0), y: y(p.1)))
                    }
                    path.addLine(to: CGPoint(x: x(points[points.count - 1].0), y: inset + h))
                    path.closeSubpath()
                    context.fill(path, with: .color(color.opacity(0.45)))
                    context.stroke(path, with: .color(color.opacity(0.8)), lineWidth: 1)
                } else {
                    // Vertical tick, height = intensity
                    var path = Path()
                    path.move(to: CGPoint(x: x(event.time), y: inset + h))
                    path.addLine(to: CGPoint(x: x(event.time), y: y(event.intensity)))
                    context.stroke(path, with: .color(color),
                                   style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
        }
    }
}
