//
//  DAWTimelineView.swift
//  HapticVideoApp
//
//  Professional DAW-style timeline with animated event markers and playhead
//

import SwiftUI

struct DAWTimelineView: View {
    @Binding var events: [HapticEvent]
    @Binding var currentTime: Double
    let videoDuration: Double
    let zoomScale: Double
    let selectedEventType: HapticEventType
    @Binding var selectedEvent: HapticEvent?
    let isPlaying: Bool
    var onSeek: (Double) -> Void
    var onAddEvent: (Double) -> Void
    var onSelectEvent: (HapticEvent) -> Void
    
    @State private var playingEventIDs: Set<UUID> = []
    
    private var pixelsPerSecond: CGFloat {
        60 * zoomScale
    }
    
    private var contentWidth: CGFloat {
        CGFloat(videoDuration) * pixelsPerSecond
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Grid Background
                gridBackground(size: geometry.size)
                
                // Event Lane Background
                eventLaneBackground(size: geometry.size)
                
                // Event Markers
                ForEach(events) { event in
                    eventMarker(event: event, height: geometry.size.height)
                }
                
                // Playhead
                playhead(height: geometry.size.height)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let time = Double(location.x / pixelsPerSecond)
                if time >= 0 && time <= videoDuration {
                    onAddEvent(time)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let time = Double(value.location.x / pixelsPerSecond)
                        let clampedTime = max(0, min(videoDuration, time))
                        onSeek(clampedTime)
                    }
            )
        }
        .onChange(of: currentTime) { _, newTime in
            updatePlayingEvents(at: newTime)
        }
    }
    
    // MARK: - Grid Background
    
    private func gridBackground(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            // Vertical grid lines (every second)
            for second in 0...Int(videoDuration) {
                let x = CGFloat(second) * pixelsPerSecond
                let isMajor = second % 5 == 0
                
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                    },
                    with: .color(isMajor ? EditorColors.gridLineMajor : EditorColors.gridLine),
                    lineWidth: 1
                )
            }
            
            // Center line for event lane
            let centerY = canvasSize.height / 2
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: 0, y: centerY))
                    path.addLine(to: CGPoint(x: canvasSize.width, y: centerY))
                },
                with: .color(EditorColors.gridLine),
                lineWidth: 1
            )
        }
    }
    
    // MARK: - Event Lane Background
    
    private func eventLaneBackground(size: CGSize) -> some View {
        // Subtle waveform-style background visualization
        Canvas { context, canvasSize in
            let centerY = canvasSize.height / 2
            
            // Draw fake waveform visualization
            for x in stride(from: 0, to: canvasSize.width, by: 3) {
                let normalized = x / canvasSize.width
                let amplitude = (sin(normalized * 20) * 0.3 + sin(normalized * 47) * 0.2) * 15
                
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: x, y: centerY - amplitude))
                        path.addLine(to: CGPoint(x: x, y: centerY + amplitude))
                    },
                    with: .color(EditorColors.surfaceHover.opacity(0.5)),
                    lineWidth: 2
                )
            }
        }
    }
    
    // MARK: - Event Marker
    
    private func eventMarker(event: HapticEvent, height: CGFloat) -> some View {
        let x = CGFloat(event.time) * pixelsPerSecond
        let isSelected = selectedEvent?.id == event.id
        let isPlaying = playingEventIDs.contains(event.id)
        let color = EditorColors.color(for: event.type)
        
        return ZStack {
            // Event shape based on type
            eventShape(for: event.type, isSelected: isSelected, isPlaying: isPlaying)
                .fill(color)
                .frame(width: eventWidth(for: event), height: eventHeight(for: event.type))
                .shadow(
                    color: isPlaying ? color.opacity(0.8) : .clear,
                    radius: isPlaying ? 10 : 0
                )
                .scaleEffect(isPlaying ? 1.2 : (isSelected ? 1.1 : 1.0))
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPlaying)
                .animation(.spring(response: 0.2), value: isSelected)
            
            // Duration indicator for continuous events
            if event.type == .continuous && event.duration > 0 {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(0.4))
                    .frame(width: CGFloat(event.duration) * pixelsPerSecond, height: 4)
                    .offset(x: CGFloat(event.duration) * pixelsPerSecond / 2)
            }
            
            // Selection ring
            if isSelected {
                Circle()
                    .stroke(color, lineWidth: 2)
                    .frame(width: 24, height: 24)
            }
        }
        .position(x: x, y: height / 2)
        .onTapGesture {
            onSelectEvent(event)
        }
        .onLongPressGesture {
            UIHaptics.deleteEvent()
            withAnimation(.spring(response: 0.3)) {
                events.removeAll { $0.id == event.id }
            }
        }
    }
    
    private func eventShape(for type: HapticEventType, isSelected: Bool, isPlaying: Bool) -> some Shape {
        switch type {
        case .transient:
            return AnyShape(Circle())
        case .impact:
            return AnyShape(RoundedRectangle(cornerRadius: 2).rotation(.degrees(45)))
        case .continuous:
            return AnyShape(RoundedRectangle(cornerRadius: 4))
        }
    }
    
    private func eventWidth(for event: HapticEvent) -> CGFloat {
        switch event.type {
        case .transient: return 14
        case .impact: return 12
        case .continuous: return 16
        }
    }
    
    private func eventHeight(for type: HapticEventType) -> CGFloat {
        switch type {
        case .transient: return 14
        case .impact: return 12
        case .continuous: return 12
        }
    }
    
    // MARK: - Playhead
    
    private func playhead(height: CGFloat) -> some View {
        let x = CGFloat(currentTime) * pixelsPerSecond
        
        return ZStack {
            // Glow effect when playing
            if isPlaying {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [EditorColors.playhead.opacity(0.3), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 20, height: height)
                    .position(x: x + 10, y: height / 2)
            }
            
            // Playhead line
            Rectangle()
                .fill(EditorColors.playhead)
                .frame(width: 2, height: height)
                .position(x: x, y: height / 2)
            
            // Top handle
            Circle()
                .fill(EditorColors.playhead)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .shadow(color: EditorColors.playhead.opacity(0.5), radius: 4)
                .position(x: x, y: 8)
            
            // Bottom handle
            Circle()
                .fill(EditorColors.playhead)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .shadow(color: EditorColors.playhead.opacity(0.5), radius: 4)
                .position(x: x, y: height - 8)
        }
        .animation(.linear(duration: 0.02), value: currentTime)
    }
    
    // MARK: - Playing Events Detection
    
    private func updatePlayingEvents(at time: Double) {
        let tolerance: Double = 0.05
        
        let newPlayingIDs = Set(events.filter { event in
            abs(event.time - time) < tolerance ||
            (event.type == .continuous && time >= event.time && time <= event.time + event.duration)
        }.map { $0.id })
        
        if newPlayingIDs != playingEventIDs {
            playingEventIDs = newPlayingIDs
        }
    }
}

// MARK: - AnyShape Helper

struct AnyShape: Shape {
    private let builder: (CGRect) -> Path
    
    init<S: Shape>(_ shape: S) {
        builder = { rect in
            shape.path(in: rect)
        }
    }
    
    func path(in rect: CGRect) -> Path {
        builder(rect)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        EditorColors.background.ignoresSafeArea()
        
        DAWTimelineView(
            events: .constant([
                HapticEvent(time: 1.0, intensity: 0.8, sharpness: 0.5, duration: 0, type: .transient),
                HapticEvent(time: 2.5, intensity: 0.9, sharpness: 0.3, duration: 0, type: .impact),
                HapticEvent(time: 4.0, intensity: 0.7, sharpness: 0.6, duration: 0.5, type: .continuous)
            ]),
            currentTime: .constant(2.0),
            videoDuration: 10.0,
            zoomScale: 1.5,
            selectedEventType: .transient,
            selectedEvent: .constant(nil),
            isPlaying: true,
            onSeek: { _ in },
            onAddEvent: { _ in },
            onSelectEvent: { _ in }
        )
        .frame(height: 100)
        .padding()
    }
}
