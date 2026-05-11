//
//  HapticEditorView.swift
//  HapticVideoApp
//
//  Premiere Pro-inspired mobile haptic editor.
//

import SwiftUI
import AVKit

struct HapticEditorView: View {
    @Binding var pattern: HapticPattern
    let videoURL: URL
    let videoDuration: Double
    var onSave: (HapticPattern) -> Void

    @StateObject private var viewModel: HapticEditorViewModel
    @Environment(\.dismiss) var dismiss

    @State private var activeTool: EditorTool = .select
    @State private var zoomScale: Double = 1.0
    @State private var selectedEvent: HapticEvent?
    @State private var lastPinchScale: CGFloat = 1.0

    init(pattern: Binding<HapticPattern>, videoURL: URL, videoDuration: Double, onSave: @escaping (HapticPattern) -> Void) {
        self._pattern = pattern
        self.videoURL = videoURL
        self.videoDuration = videoDuration
        self.onSave = onSave
        self._viewModel = StateObject(wrappedValue: HapticEditorViewModel(
            pattern: pattern.wrappedValue,
            videoURL: videoURL,
            videoDuration: videoDuration
        ))
    }

    var body: some View {
        ZStack {
            EditorColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                videoMonitor
                transportBar
                toolPalette
                timelineSection
                if let event = selectedEvent {
                    inspector(for: event)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear {
            UIHaptics.prepare()
            viewModel.setupPlayer()
        }
        .onDisappear {
            viewModel.cleanup()
        }
        // Keep `selectedEvent` in sync with the source-of-truth events array
        .onChange(of: viewModel.events) { _, newEvents in
            if let sel = selectedEvent,
               let updated = newEvents.first(where: { $0.id == sel.id }) {
                selectedEvent = updated
            } else if selectedEvent != nil,
                      !newEvents.contains(where: { $0.id == selectedEvent?.id }) {
                selectedEvent = nil
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            iconButton(systemName: "chevron.left") {
                dismiss()
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Haptic Editor")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(EditorColors.textPrimary)
                Text("\(viewModel.events.count) events  •  \(formatTimeShort(videoDuration))")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(EditorColors.textTertiary)
            }

            Spacer()

            // Undo/redo placeholders kept visually for Premiere parity
            iconButton(systemName: "arrow.uturn.backward") { UIHaptics.buttonTap() }
                .disabled(true)
                .opacity(0.4)
            iconButton(systemName: "arrow.uturn.forward") { UIHaptics.buttonTap() }
                .disabled(true)
                .opacity(0.4)

            Button {
                UIHaptics.success()
                var updated = pattern
                updated.events = viewModel.events
                onSave(updated)
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(EditorColors.accent)
                    )
            }
        }
        .padding(.horizontal, 12)
        .frame(height: EditorDimensions.topBarHeight)
        .background(EditorColors.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(EditorColors.divider).frame(height: 1)
        }
    }

    // MARK: - Video Monitor

    private var videoMonitor: some View {
        ZStack {
            EditorColors.panel

            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .disabled(true)
                    .aspectRatio(16/9, contentMode: .fit)
            } else {
                ProgressView()
                    .tint(EditorColors.accent)
            }

            // Floating timecode like Premiere monitor
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.isPlaying ? EditorColors.playhead : EditorColors.textTertiary)
                            .frame(width: 6, height: 6)
                        Text(formatTime(viewModel.currentTime))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(8)
                }
                Spacer()
            }
        }
        .frame(height: 200)
        .overlay(alignment: .bottom) {
            Rectangle().fill(EditorColors.divider).frame(height: 1)
        }
    }

    // MARK: - Transport Bar

    private var transportBar: some View {
        HStack(spacing: 16) {
            Spacer()

            transportIcon("backward.end.fill") {
                viewModel.seek(to: 0)
            }
            transportIcon("gobackward.5") {
                viewModel.skipBackward()
            }

            Button {
                if viewModel.isPlaying { UIHaptics.pause() } else { UIHaptics.play() }
                viewModel.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(EditorColors.accent)
                        .frame(width: 42, height: 42)
                        .shadow(color: EditorColors.accent.opacity(0.4), radius: 8, y: 2)
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .offset(x: viewModel.isPlaying ? 0 : 1.5)
                }
            }

            transportIcon("goforward.5") {
                viewModel.skipForward()
            }
            transportIcon("forward.end.fill") {
                viewModel.seek(to: videoDuration - 0.5)
            }

            Spacer()

            // Zoom controls — Premiere-style
            HStack(spacing: 6) {
                transportIcon("minus.magnifyingglass", size: 28) {
                    setZoom(zoomScale - 0.25)
                }
                Text("\(Int(zoomScale * 100))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(EditorColors.textSecondary)
                    .frame(width: 38)
                transportIcon("plus.magnifyingglass", size: 28) {
                    setZoom(zoomScale + 0.25)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(EditorColors.trackBackground)
            )
        }
        .padding(.horizontal, 12)
        .frame(height: EditorDimensions.transportHeight)
        .background(EditorColors.panel)
    }

    private func setZoom(_ newValue: Double) {
        UIHaptics.zoom()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            zoomScale = max(0.5, min(4.0, newValue))
        }
    }

    private func transportIcon(_ name: String, size: CGFloat = 32, action: @escaping () -> Void) -> some View {
        Button {
            UIHaptics.buttonTap()
            action()
        } label: {
            Image(systemName: name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(EditorColors.textPrimary)
                .frame(width: size, height: size)
        }
    }

    // MARK: - Tool Palette

    private var toolPalette: some View {
        HStack(spacing: 6) {
            ForEach(EditorTool.allCases) { tool in
                toolButton(tool)
            }

            Spacer()

            Button {
                guard let event = selectedEvent else { return }
                UIHaptics.previewEventType(event.type)
                viewModel.previewEvent(event)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(selectedEvent == nil ? EditorColors.textTertiary : EditorColors.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(EditorColors.surfaceElevated)
                    )
            }
            .disabled(selectedEvent == nil)

            Button {
                guard !viewModel.events.isEmpty else { return }
                UIHaptics.deleteEvent()
                withAnimation(.spring(response: 0.3)) {
                    viewModel.clearAllEvents()
                    selectedEvent = nil
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(viewModel.events.isEmpty ? EditorColors.textTertiary : EditorColors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(EditorColors.surfaceElevated)
                    )
            }
            .disabled(viewModel.events.isEmpty)
        }
        .padding(.horizontal, 12)
        .frame(height: EditorDimensions.toolbarHeight)
        .background(EditorColors.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(EditorColors.divider).frame(height: 1)
        }
    }

    private func toolButton(_ tool: EditorTool) -> some View {
        let active = activeTool == tool
        return Button {
            UIHaptics.buttonTap()
            if let preview = tool.eventType { UIHaptics.previewEventType(preview) }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                activeTool = tool
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tool.iconName)
                    .font(.system(size: 10, weight: .bold))
                Text(tool.label.uppercased())
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(active ? .white : EditorColors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(active ? tool.color : EditorColors.surfaceElevated)
            )
        }
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        DAWTimelineView(
            events: $viewModel.events,
            currentTime: $viewModel.currentTime,
            selectedEvent: $selectedEvent,
            videoDuration: videoDuration,
            zoomScale: zoomScale,
            activeTool: activeTool,
            isPlaying: viewModel.isPlaying,
            thumbnails: viewModel.thumbnails,
            onSeek: { time in
                UIHaptics.scrub()
                viewModel.seek(to: time)
            },
            onAddEvent: { time, type in
                UIHaptics.addEvent()
                let event = HapticEvent(
                    time: time,
                    intensity: 0.8,
                    sharpness: 0.5,
                    duration: type == .continuous ? 0.25 : 0,
                    type: type
                )
                viewModel.addEvent(event)
                withAnimation(.spring(response: 0.3)) {
                    selectedEvent = event
                }
            },
            onMoveEvent: { id, newTime in
                viewModel.updateEvent(id: id, time: newTime)
            },
            onDeleteEvent: { id in
                withAnimation(.spring(response: 0.3)) {
                    viewModel.deleteEvent(id: id)
                    if selectedEvent?.id == id { selectedEvent = nil }
                }
            },
            onSelectEvent: { event in
                withAnimation(.spring(response: 0.3)) {
                    selectedEvent = event
                }
            }
        )
        .frame(maxHeight: .infinity)
        .background(EditorColors.trackBackground)
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    let delta = value / lastPinchScale
                    lastPinchScale = value
                    let newZoom = zoomScale * Double(delta)
                    zoomScale = max(0.5, min(4.0, newZoom))
                }
                .onEnded { _ in
                    lastPinchScale = 1.0
                    UIHaptics.snap()
                }
        )
    }

    // MARK: - Inspector

    private func inspector(for event: HapticEvent) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(EditorColors.color(for: event.type))
                    .frame(width: 8, height: 8)
                Text(event.type.rawValue.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(EditorColors.textPrimary)
                Text("@ \(formatTime(event.time))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(EditorColors.textTertiary)

                Spacer()

                Button {
                    UIHaptics.previewEventType(event.type)
                    viewModel.previewEvent(event)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 11))
                        .foregroundColor(EditorColors.accent)
                        .padding(7)
                        .background(EditorColors.accent.opacity(0.18), in: Circle())
                }

                Button {
                    UIHaptics.deleteEvent()
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.deleteEvent(id: event.id)
                        selectedEvent = nil
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(EditorColors.playhead)
                        .padding(7)
                        .background(EditorColors.playhead.opacity(0.18), in: Circle())
                }

                Button {
                    UIHaptics.buttonTap()
                    withAnimation(.spring(response: 0.3)) {
                        selectedEvent = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(EditorColors.textSecondary)
                        .padding(7)
                        .background(EditorColors.surfaceElevated, in: Circle())
                }
            }

            HStack(spacing: 12) {
                inspectorSlider(
                    title: "INTENSITY",
                    value: Double(event.intensity),
                    color: EditorColors.accent
                ) { newValue in
                    viewModel.updateEvent(id: event.id, intensity: Float(newValue))
                }

                inspectorSlider(
                    title: "SHARPNESS",
                    value: Double(event.sharpness),
                    color: EditorColors.impact
                ) { newValue in
                    viewModel.updateEvent(id: event.id, sharpness: Float(newValue))
                }

                if event.type == .continuous {
                    inspectorSlider(
                        title: "DURATION",
                        value: event.duration,
                        range: 0.05...2.0,
                        suffix: "s",
                        color: EditorColors.continuous
                    ) { newValue in
                        viewModel.updateEvent(id: event.id, duration: newValue)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(EditorColors.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(EditorColors.divider).frame(height: 1)
        }
    }

    private func inspectorSlider(
        title: String,
        value: Double,
        range: ClosedRange<Double> = 0...1,
        suffix: String = "",
        color: Color,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        let percent = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(EditorColors.textTertiary)
                Spacer()
                Text(suffix.isEmpty
                     ? String(format: "%.0f%%", value * 100)
                     : String(format: "%.2f%@", value, suffix))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(EditorColors.surfaceElevated)
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: max(8, geo.size.width * CGFloat(percent)), height: 8)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                        .shadow(color: color.opacity(0.6), radius: 4)
                        .offset(x: max(0, min(geo.size.width - 14, geo.size.width * CGFloat(percent) - 7)))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let x = max(0, min(geo.size.width, drag.location.x))
                            let p = Double(x / geo.size.width)
                            let newValue = range.lowerBound + p * (range.upperBound - range.lowerBound)
                            onChange(newValue)
                            UIHaptics.selectionChanged()
                        }
                )
            }
            .frame(height: 18)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Small Helpers

    private func iconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIHaptics.buttonTap()
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(EditorColors.textSecondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(EditorColors.surfaceElevated)
                )
        }
    }

    private func formatTime(_ time: Double) -> String {
        let safe = max(0, time)
        let minutes = Int(safe) / 60
        let seconds = Int(safe) % 60
        let centi = Int((safe.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, centi)
    }

    private func formatTimeShort(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Corner Radius helpers

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Equatable for HapticEvent (used by onChange)

extension HapticEvent: Equatable {
    static func == (lhs: HapticEvent, rhs: HapticEvent) -> Bool {
        lhs.id == rhs.id
        && lhs.time == rhs.time
        && lhs.intensity == rhs.intensity
        && lhs.sharpness == rhs.sharpness
        && lhs.duration == rhs.duration
        && lhs.type == rhs.type
    }
}

// MARK: - Preview

#Preview {
    HapticEditorView(
        pattern: .constant(HapticPattern(
            videoID: "test-video",
            events: [
                HapticEvent(time: 1.0, intensity: 0.8, sharpness: 0.5, duration: 0, type: .transient),
                HapticEvent(time: 2.0, intensity: 0.6, sharpness: 0.7, duration: 0.5, type: .continuous),
                HapticEvent(time: 3.5, intensity: 0.9, sharpness: 0.3, duration: 0, type: .impact)
            ]
        )),
        videoURL: URL(string: "https://example.com/video.mp4")!,
        videoDuration: 30.0,
        onSave: { _ in }
    )
}
