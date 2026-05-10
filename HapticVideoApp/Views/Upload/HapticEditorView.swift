//
//  HapticEditorView.swift
//  HapticVideoApp
//
//  Professional DAW-style haptic editor with dark theme and haptic UI feedback
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
    
    @State private var selectedEventType: HapticEventType = .transient
    @State private var zoomScale: Double = 1.0
    @State private var selectedEvent: HapticEvent?
    @State private var showExportOptions = false
    @State private var isTimelineExpanded = false
    
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
            // Background
            EditorColors.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top Navigation Bar
                editorNavBar
                
                // Video Player Section
                videoPlayerSection
                    .frame(height: isTimelineExpanded ? 150 : 220)
                    .animation(.spring(response: 0.3), value: isTimelineExpanded)
                
                // Transport Controls
                transportControls
                    .padding(.vertical, 12)
                    .background(EditorColors.trackBackground)
                
                // Event Type Selector
                eventTypeSelector
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                
                // Timeline Section
                timelineSection
                    .frame(maxHeight: .infinity)
                
                // Event Inspector (if selected)
                if let event = selectedEvent {
                    eventInspector(event: event)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            UIHaptics.prepare()
            viewModel.setupPlayer()
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .sheet(isPresented: $showExportOptions) {
            exportOptionsSheet
        }
    }
    
    // MARK: - Navigation Bar
    
    private var editorNavBar: some View {
        HStack {
            Button {
                UIHaptics.buttonTap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(EditorColors.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(EditorColors.surfaceElevated)
                    .clipShape(Circle())
            }
            
            Spacer()
            
            VStack(spacing: 2) {
                Text("HAPTIC EDITOR")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(EditorColors.textSecondary)
                
                Text("\(viewModel.events.count) events")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(EditorColors.textTertiary)
            }
            
            Spacer()
            
            Button {
                UIHaptics.success()
                savePattern()
            } label: {
                Text("Save")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(EditorColors.accent)
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(EditorColors.trackBackground)
    }
    
    // MARK: - Video Player Section
    
    private var videoPlayerSection: some View {
        ZStack {
            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .disabled(true)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(EditorColors.surfaceElevated, lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(EditorColors.trackBackground)
                    .overlay(
                        ProgressView()
                            .tint(EditorColors.accent)
                    )
            }
            
            // Time Overlay
            VStack {
                HStack {
                    Spacer()
                    Text(formatTime(viewModel.currentTime))
                        .font(.system(size: 24, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .padding(12)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // MARK: - Transport Controls
    
    private var transportControls: some View {
        HStack(spacing: 24) {
            // Skip Backward
            Button {
                UIHaptics.buttonTap()
                viewModel.skipBackward()
            } label: {
                Image(systemName: "gobackward.5")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(EditorColors.textPrimary)
            }
            
            // Play/Pause
            Button {
                if viewModel.isPlaying {
                    UIHaptics.pause()
                } else {
                    UIHaptics.play()
                }
                viewModel.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(viewModel.isPlaying ? EditorColors.accent : EditorColors.surfaceElevated)
                        .frame(width: 56, height: 56)
                        .shadow(color: viewModel.isPlaying ? EditorColors.accent.opacity(0.5) : .clear, radius: 10)
                    
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(viewModel.isPlaying ? .white : EditorColors.textPrimary)
                        .offset(x: viewModel.isPlaying ? 0 : 2)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: viewModel.isPlaying)
            
            // Skip Forward
            Button {
                UIHaptics.buttonTap()
                viewModel.skipForward()
            } label: {
                Image(systemName: "goforward.5")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(EditorColors.textPrimary)
            }
            
            Spacer()
            
            // Zoom Controls
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        zoomScale = max(0.5, zoomScale - 0.5)
                    }
                    UIHaptics.zoom()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(EditorColors.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(EditorColors.surfaceElevated)
                        .cornerRadius(6)
                }
                .disabled(zoomScale <= 0.5)
                
                Text("\(Int(zoomScale * 100))%")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(EditorColors.textSecondary)
                    .frame(width: 50)
                
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        zoomScale = min(3.0, zoomScale + 0.5)
                    }
                    UIHaptics.zoom()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(EditorColors.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(EditorColors.surfaceElevated)
                        .cornerRadius(6)
                }
                .disabled(zoomScale >= 3.0)
            }
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Event Type Selector
    
    private var eventTypeSelector: some View {
        HStack(spacing: 8) {
            Text("ADD")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(EditorColors.textTertiary)
            
            ForEach([HapticEventType.transient, .impact, .continuous], id: \.self) { type in
                Button {
                    selectedEventType = type
                    UIHaptics.previewEventType(type)
                } label: {
                    HStack(spacing: 6) {
                        eventTypeIcon(type)
                            .font(.system(size: 10))
                        Text(type.rawValue.uppercased())
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        selectedEventType == type ?
                        EditorColors.color(for: type).opacity(0.3) :
                        EditorColors.surfaceElevated
                    )
                    .foregroundColor(
                        selectedEventType == type ?
                        EditorColors.color(for: type) :
                        EditorColors.textSecondary
                    )
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                selectedEventType == type ?
                                EditorColors.color(for: type) :
                                Color.clear,
                                lineWidth: 1
                            )
                    )
                }
            }
            
            Spacer()
            
            // Clear All Button
            Button {
                UIHaptics.deleteEvent()
                withAnimation(.spring(response: 0.3)) {
                    viewModel.events.removeAll()
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(EditorColors.textTertiary)
                    .frame(width: 32, height: 32)
                    .background(EditorColors.surfaceElevated)
                    .cornerRadius(6)
            }
            .disabled(viewModel.events.isEmpty)
            .opacity(viewModel.events.isEmpty ? 0.5 : 1)
        }
    }
    
    private func eventTypeIcon(_ type: HapticEventType) -> some View {
        Group {
            switch type {
            case .transient:
                Circle().fill(EditorColors.transient)
            case .impact:
                Rectangle().fill(EditorColors.impact).rotationEffect(.degrees(45))
            case .continuous:
                RoundedRectangle(cornerRadius: 2).fill(EditorColors.continuous)
            }
        }
        .frame(width: 8, height: 8)
    }
    
    // MARK: - Timeline Section
    
    private var timelineSection: some View {
        VStack(spacing: 0) {
            // Time Ruler
            timeRuler
                .frame(height: 24)
            
            // Timeline Content
            ScrollView(.horizontal, showsIndicators: false) {
                DAWTimelineView(
                    events: $viewModel.events,
                    currentTime: $viewModel.currentTime,
                    videoDuration: videoDuration,
                    zoomScale: zoomScale,
                    selectedEventType: selectedEventType,
                    selectedEvent: $selectedEvent,
                    isPlaying: viewModel.isPlaying,
                    onSeek: { time in
                        UIHaptics.scrub()
                        viewModel.seek(to: time)
                    },
                    onAddEvent: { time in
                        addEventAt(time: time)
                    },
                    onSelectEvent: { event in
                        UIHaptics.selectEvent()
                        withAnimation(.spring(response: 0.3)) {
                            selectedEvent = event
                        }
                    }
                )
                .frame(width: max(UIScreen.main.bounds.width, CGFloat(videoDuration * 60 * zoomScale)))
                .frame(height: 100)
            }
            .background(EditorColors.trackBackground)
        }
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }
    
    private var timeRuler: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let pixelsPerSecond = 60 * zoomScale
                
                for second in 0...Int(videoDuration) {
                    let x = CGFloat(second) * pixelsPerSecond
                    
                    // Major tick every 5 seconds
                    let isMajor = second % 5 == 0
                    let tickHeight: CGFloat = isMajor ? 10 : 5
                    
                    context.stroke(
                        Path { path in
                            path.move(to: CGPoint(x: x, y: size.height))
                            path.addLine(to: CGPoint(x: x, y: size.height - tickHeight))
                        },
                        with: .color(isMajor ? EditorColors.gridLineMajor : EditorColors.gridLine),
                        lineWidth: 1
                    )
                    
                    // Time labels for major ticks
                    if isMajor {
                        let timeText = formatTimeShort(Double(second))
                        context.draw(
                            Text(timeText)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(EditorColors.textTertiary),
                            at: CGPoint(x: x, y: 8)
                        )
                    }
                }
            }
        }
        .background(EditorColors.timeRuler)
    }
    
    // MARK: - Event Inspector
    
    private func eventInspector(event: HapticEvent) -> some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Circle()
                    .fill(EditorColors.color(for: event.type))
                    .frame(width: 12, height: 12)
                
                Text(event.type.rawValue.uppercased())
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(EditorColors.textPrimary)
                
                Text("@ \(formatTime(event.time))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(EditorColors.textSecondary)
                
                Spacer()
                
                Button {
                    UIHaptics.previewEventType(event.type)
                    viewModel.previewEvent(event)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 12))
                        .foregroundColor(EditorColors.accent)
                        .frame(width: 32, height: 32)
                        .background(EditorColors.accent.opacity(0.2))
                        .cornerRadius(6)
                }
                
                Button {
                    UIHaptics.buttonTap()
                    withAnimation(.spring(response: 0.3)) {
                        selectedEvent = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(EditorColors.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(EditorColors.surfaceElevated)
                        .cornerRadius(6)
                }
            }
            
            // Sliders
            HStack(spacing: 24) {
                inspectorSlider(
                    title: "INTENSITY",
                    value: Binding(
                        get: { Double(event.intensity) },
                        set: { updateEvent(event, intensity: Float($0)) }
                    ),
                    color: EditorColors.accent
                )
                
                inspectorSlider(
                    title: "SHARPNESS",
                    value: Binding(
                        get: { Double(event.sharpness) },
                        set: { updateEvent(event, sharpness: Float($0)) }
                    ),
                    color: EditorColors.impact
                )
                
                if event.type == .continuous {
                    inspectorSlider(
                        title: "DURATION",
                        value: Binding(
                            get: { event.duration },
                            set: { updateEvent(event, duration: $0) }
                        ),
                        range: 0.1...2.0,
                        color: EditorColors.continuous
                    )
                }
                
                // Delete Button
                Button {
                    UIHaptics.deleteEvent()
                    deleteEvent(event)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14))
                        Text("DELETE")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    }
                    .foregroundColor(.red)
                    .frame(width: 60, height: 60)
                    .background(Color.red.opacity(0.15))
                    .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(EditorColors.surfaceElevated)
        .cornerRadius(16, corners: [.topLeft, .topRight])
    }
    
    private func inspectorSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double> = 0...1,
        color: Color
    ) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(EditorColors.textTertiary)
            
            ZStack {
                Circle()
                    .stroke(EditorColors.surfaceHover, lineWidth: 4)
                
                Circle()
                    .trim(from: 0, to: CGFloat((value.wrappedValue - range.lowerBound) / (range.upperBound - range.lowerBound)))
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                
                Text(String(format: "%.0f", value.wrappedValue * 100))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(EditorColors.textPrimary)
            }
            .frame(width: 50, height: 50)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let delta = -gesture.translation.height / 100
                        let newValue = value.wrappedValue + delta
                        value.wrappedValue = min(range.upperBound, max(range.lowerBound, newValue))
                        UIHaptics.selectionChanged()
                    }
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func addEventAt(time: Double) {
        UIHaptics.addEvent()
        let newEvent = HapticEvent(
            time: time,
            intensity: 0.8,
            sharpness: 0.5,
            duration: selectedEventType == .continuous ? 0.2 : 0,
            type: selectedEventType
        )
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            viewModel.events.append(newEvent)
            viewModel.events.sort { $0.time < $1.time }
        }
        viewModel.reloadHapticPattern()
    }
    
    private func updateEvent(_ event: HapticEvent, intensity: Float? = nil, sharpness: Float? = nil, duration: Double? = nil) {
        if let index = viewModel.events.firstIndex(where: { $0.id == event.id }) {
            var updatedEvent = viewModel.events[index]
            if let intensity = intensity { updatedEvent.intensity = intensity }
            if let sharpness = sharpness { updatedEvent.sharpness = sharpness }
            if let duration = duration { updatedEvent.duration = duration }
            viewModel.events[index] = updatedEvent
        }
    }
    
    private func deleteEvent(_ event: HapticEvent) {
        withAnimation(.spring(response: 0.3)) {
            viewModel.events.removeAll { $0.id == event.id }
            selectedEvent = nil
        }
        viewModel.reloadHapticPattern()
    }
    
    private func savePattern() {
        var updatedPattern = pattern
        updatedPattern.events = viewModel.events
        onSave(updatedPattern)
        dismiss()
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, milliseconds)
    }
    
    private func formatTimeShort(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Export Options Sheet
    
    private var exportOptionsSheet: some View {
        NavigationView {
            List {
                Section("Export Format") {
                    Button {
                        showExportOptions = false
                    } label: {
                        Label("JSON File", systemImage: "doc.text")
                    }
                    
                    Button {
                        showExportOptions = false
                    } label: {
                        Label("AHAP File (Apple Haptic)", systemImage: "waveform")
                    }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showExportOptions = false
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Corner Radius Extension

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
