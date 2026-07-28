//
//  DAWTimelineView.swift
//  HapticVideoApp
//
//  Multi-lane, Premiere-style timeline. One lane per haptic event type so
//  events of different types never overlap. Tap on a lane to add an event of
//  that type at the tap location; long-press to delete an event; drag to move.
//  A dedicated scrub strip handles playhead dragging so taps and drags on lanes
//  do not conflict.
//

import SwiftUI

struct DAWTimelineView: View {
    @Binding var events: [HapticEvent]
    @Binding var currentTime: Double
    @Binding var selectedEvent: HapticEvent?

    let videoDuration: Double
    let zoomScale: Double
    let activeTool: EditorTool
    let isPlaying: Bool
    let thumbnails: [UIImage]

    var onSeek: (Double) -> Void
    var onAddEvent: (Double, HapticEventType) -> Void
    var onMoveEvent: (UUID, Double) -> Void
    var onDeleteEvent: (UUID) -> Void
    var onSelectEvent: (HapticEvent) -> Void
    /// Curve point edits on continuous events. Wire in parent (see INTEGRATION).
    var onUpdateCurve: ((UUID, [HapticCurvePoint]) -> Void)? = nil

    private static let trackOrder: [HapticEventType] = [.transient, .impact, .continuous]

    private var pixelsPerSecond: CGFloat { EditorDimensions.basePixelsPerSecond * zoomScale }
    private var contentWidth: CGFloat {
        max(1, CGFloat(videoDuration) * pixelsPerSecond)
    }
    private var totalTrackHeight: CGFloat {
        EditorDimensions.videoTrackHeight + CGFloat(Self.trackOrder.count) * EditorDimensions.hapticTrackHeight
    }

    @State private var draggingEventID: UUID?
    @State private var dragOffsetSeconds: Double = 0
    @State private var lastScrubTime: Double?
    @State private var snapEnabled = true
    @State private var lastSnappedTime: Double?
    @State private var curveDragIndex: Int?
    @State private var curveDragStartValue: Float = 0

    var body: some View {
        HStack(spacing: 0) {
            trackLabelsColumn
                .frame(width: EditorDimensions.trackHeaderWidth)
                .background(EditorColors.trackHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    timeRuler
                        .frame(width: contentWidth, height: EditorDimensions.timeRulerHeight)

                    videoTrack
                        .frame(width: contentWidth, height: EditorDimensions.videoTrackHeight)

                    ForEach(Self.trackOrder, id: \.self) { type in
                        hapticTrack(for: type)
                            .frame(width: contentWidth, height: EditorDimensions.hapticTrackHeight)
                    }
                }
                .overlay(alignment: .topLeading) {
                    playhead
                }
            }
            .background(EditorColors.trackBackground)
        }
    }

    // MARK: - Track Labels (sticky left column)

    private var trackLabelsColumn: some View {
        VStack(spacing: 0) {
            // Snap-to-grid toggle, tucked into the ruler-height gap
            Button {
                snapEnabled.toggle()
                UIHaptics.buttonTap()
            } label: {
                // ponytail: SF Symbols has no magnet; grid icon reads as snap-to-grid
                Image(systemName: snapEnabled ? "square.grid.3x3.fill" : "square.grid.3x3")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(snapEnabled ? EditorColors.accent : EditorColors.textTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: EditorDimensions.timeRulerHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            trackLabel(icon: "film", title: "V1", color: EditorColors.textSecondary, height: EditorDimensions.videoTrackHeight)

            ForEach(Self.trackOrder, id: \.self) { type in
                trackLabel(
                    icon: EditorColors.icon(for: type),
                    title: shortTitle(for: type),
                    color: EditorColors.color(for: type),
                    height: EditorDimensions.hapticTrackHeight
                )
            }
        }
    }

    private func trackLabel(icon: String, title: String, color: Color, height: CGFloat) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(EditorColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(EditorColors.trackSeparator)
                .frame(height: 1)
        }
    }

    private func shortTitle(for type: HapticEventType) -> String {
        switch type {
        case .transient:  return "TAP"
        case .impact:     return "BEAT"
        case .continuous: return "HOLD"
        }
    }

    // MARK: - Time Ruler (also scrub strip)

    private var timeRuler: some View {
        Canvas { context, size in
            let ppr = pixelsPerSecond
            // Choose label interval based on zoom so labels don't overlap
            let labelInterval: Int = ppr >= 80 ? 1 : (ppr >= 40 ? 2 : (ppr >= 20 ? 5 : 10))

            for second in 0...Int(videoDuration) {
                let x = CGFloat(second) * ppr
                let isMajor = second % labelInterval == 0
                let tickHeight: CGFloat = isMajor ? 8 : 4

                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: x, y: size.height))
                        p.addLine(to: CGPoint(x: x, y: size.height - tickHeight))
                    },
                    with: .color(isMajor ? EditorColors.gridLineMajor : EditorColors.gridLineMinor),
                    lineWidth: 1
                )

                if isMajor {
                    context.draw(
                        Text(formatTimeShort(Double(second)))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(EditorColors.textTertiary),
                        at: CGPoint(x: x + 2, y: 8),
                        anchor: .leading
                    )
                }
            }
        }
        .background(EditorColors.timeRuler)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let t = max(0, min(videoDuration, Double(value.location.x / pixelsPerSecond)))
                    if let prev = lastScrubTime {
                        tickCrossedEvents(from: prev, to: t)
                    }
                    lastScrubTime = t
                    onSeek(t)
                }
                .onEnded { _ in
                    lastScrubTime = nil
                }
        )
    }

    /// Fire one scrub tick when the playhead crosses an event, scaled to its
    /// intensity — so scrubbing lets you feel the pattern. Throttled to one
    /// tick per crossing, not per frame.
    private func tickCrossedEvents(from prev: Double, to t: Double) {
        guard prev != t else { return }
        let lo = min(prev, t)
        let hi = max(prev, t)
        // ponytail: multiple events crossed in one frame collapse to the strongest tick
        if let hit = events.filter({ $0.time > lo && $0.time <= hi }).max(by: { $0.intensity < $1.intensity }) {
            UIHaptics.scrub(intensity: CGFloat(hit.intensity))
        }
    }

    // MARK: - Video Track (frame strip)

    private var videoTrack: some View {
        ZStack(alignment: .leading) {
            EditorColors.panel

            if !thumbnails.isEmpty {
                HStack(spacing: 0) {
                    ForEach(0..<thumbnails.count, id: \.self) { i in
                        Image(uiImage: thumbnails[i])
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(
                                width: contentWidth / CGFloat(thumbnails.count),
                                height: EditorDimensions.videoTrackHeight
                            )
                            .clipped()
                    }
                }
            } else {
                Rectangle()
                    .fill(LinearGradient(
                        colors: [EditorColors.surfaceElevated, EditorColors.panel],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
            }

            // Subtle highlight overlay
            Rectangle()
                .fill(EditorColors.accent.opacity(0.06))
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(EditorColors.trackSeparator)
                .frame(height: 1)
        }
    }

    // MARK: - Haptic Track (one per type)

    private func hapticTrack(for type: HapticEventType) -> some View {
        let laneColor = EditorColors.color(for: type)
        let eventsForType = events.filter { $0.type == type }

        return ZStack(alignment: .leading) {
            // Lane background with subtle grid
            gridBackground(highlightColor: laneColor)

            // Events on this lane
            ForEach(eventsForType) { event in
                eventMarker(event: event, laneColor: laneColor)
            }
        }
        .clipped()
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(EditorColors.trackSeparator)
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        // Tap to add — works because we use TapGesture (not a 0-distance drag).
        .onTapGesture { location in
            let time = Double(location.x / pixelsPerSecond)
            guard time >= 0 && time <= videoDuration else { return }
            if activeTool == .select {
                onSeek(time)
            } else if let eventType = activeTool.eventType {
                onAddEvent(time, eventType)
            } else {
                onAddEvent(time, type)
            }
        }
    }

    private func gridBackground(highlightColor: Color) -> some View {
        Canvas { context, size in
            let ppr = pixelsPerSecond
            for second in 0...Int(videoDuration) {
                let x = CGFloat(second) * ppr
                let isMajor = second % 5 == 0
                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                    },
                    with: .color(isMajor ? EditorColors.gridLineMajor : EditorColors.gridLineMinor),
                    lineWidth: 1
                )
            }

            // Faint center line tinted with lane color
            let centerY = size.height / 2
            context.stroke(
                Path { p in
                    p.move(to: CGPoint(x: 0, y: centerY))
                    p.addLine(to: CGPoint(x: size.width, y: centerY))
                },
                with: .color(highlightColor.opacity(0.08)),
                lineWidth: 1
            )
        }
        .background(EditorColors.trackBackground)
    }

    // MARK: - Event Marker

    private func eventMarker(event: HapticEvent, laneColor: Color) -> some View {
        let isSelected = selectedEvent?.id == event.id
        let isActive = isEventActive(event)
        let intensityScale = CGFloat(0.5 + 0.5 * event.intensity)

        let displayTime: Double = (draggingEventID == event.id) ? event.time + dragOffsetSeconds : event.time
        let x = CGFloat(max(0, min(videoDuration, displayTime))) * pixelsPerSecond

        return Group {
            if event.type == .continuous && event.duration > 0 {
                continuousEventBar(event: event, laneColor: laneColor, isSelected: isSelected, isActive: isActive, intensityScale: intensityScale)
                    .position(
                        x: x + (CGFloat(event.duration) * pixelsPerSecond) / 2,
                        y: EditorDimensions.hapticTrackHeight / 2
                    )
            } else {
                pointEventMarker(event: event, laneColor: laneColor, isSelected: isSelected, isActive: isActive, intensityScale: intensityScale)
                    .position(x: x, y: EditorDimensions.hapticTrackHeight / 2)
            }
        }
        .onTapGesture {
            UIHaptics.selectEvent()
            onSelectEvent(event)
        }
        .gesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    UIHaptics.deleteEvent()
                    onDeleteEvent(event.id)
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    guard curveDragIndex == nil else { return }
                    if draggingEventID != event.id {
                        draggingEventID = event.id
                        UIHaptics.dragEvent()
                        onSelectEvent(event)
                    }
                    let raw = event.time + Double(value.translation.width / pixelsPerSecond)
                    let snapped = snappedTime(raw)
                    if snapEnabled, snapped != lastSnappedTime {
                        UIHaptics.snap()
                        lastSnappedTime = snapped
                    }
                    dragOffsetSeconds = snapped - event.time
                }
                .onEnded { value in
                    guard draggingEventID == event.id else { return }
                    let raw = event.time + Double(value.translation.width / pixelsPerSecond)
                    let newTime = max(0, min(videoDuration - 0.05, snappedTime(raw)))
                    onMoveEvent(event.id, newTime)
                    draggingEventID = nil
                    dragOffsetSeconds = 0
                    lastSnappedTime = nil
                    UIHaptics.dropEvent()
                }
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isActive)
        .animation(.spring(response: 0.2), value: isSelected)
    }

    private func pointEventMarker(event: HapticEvent, laneColor: Color, isSelected: Bool, isActive: Bool, intensityScale: CGFloat) -> some View {
        let baseSize: CGFloat = 18
        return ZStack {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white, lineWidth: 1.5)
                    .frame(width: baseSize + 8, height: baseSize + 8)
            }

            Group {
                if event.type == .transient {
                    Circle().fill(laneColor)
                } else {
                    RoundedRectangle(cornerRadius: 3).fill(laneColor)
                        .rotationEffect(.degrees(45))
                }
            }
            .frame(width: baseSize * intensityScale, height: baseSize * intensityScale)
            .shadow(color: isActive ? laneColor.opacity(0.9) : .clear, radius: isActive ? 8 : 0)
            .scaleEffect(isActive ? 1.2 : 1.0)
        }
        // 44pt hit target; visuals unchanged
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }

    private func continuousEventBar(event: HapticEvent, laneColor: Color, isSelected: Bool, isActive: Bool, intensityScale: CGFloat) -> some View {
        let width = max(8, CGFloat(event.duration) * pixelsPerSecond)
        let height: CGFloat = 22 * intensityScale
        let hasCurve = (event.intensityCurve?.count ?? 0) > 1

        return ZStack {
            if isSelected {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.white, lineWidth: 1.5)
                    .frame(width: width + 6, height: height + 6)
            }
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(
                    // Curve events get a faint block so the envelope reads on top
                    colors: hasCurve
                        ? [laneColor.opacity(0.30), laneColor.opacity(0.15)]
                        : [laneColor.opacity(0.95), laneColor.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .frame(width: width, height: height)
                .overlay {
                    if hasCurve, let curve = event.intensityCurve {
                        envelopeWaveform(curve: curve, duration: event.duration, laneColor: laneColor)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(laneColor, lineWidth: 1)
                )
                .overlay {
                    if isSelected, hasCurve, let curve = event.intensityCurve {
                        curveHandles(event: event, curve: curve, width: width, height: height, laneColor: laneColor)
                    }
                }
                .shadow(color: isActive ? laneColor.opacity(0.9) : .clear, radius: isActive ? 8 : 0)
                .scaleEffect(y: isActive ? 1.15 : 1.0, anchor: .center)
        }
        // 44pt hit target; visuals unchanged
        .frame(width: max(width, 44), height: EditorDimensions.hapticTrackHeight)
        .contentShape(Rectangle())
    }

    /// Draggable handles on a selected continuous event's curve points.
    /// Vertical drag changes that point's value (0–1) via onUpdateCurve.
    private func curveHandles(event: HapticEvent, curve: [HapticCurvePoint], width: CGFloat, height: CGFloat, laneColor: Color) -> some View {
        ForEach(curve.indices, id: \.self) { i in
            let x = CGFloat(max(0, min(1, curve[i].time / event.duration))) * width
            let y = height * (1 - CGFloat(max(0, min(1, curve[i].value))))
            Circle()
                .fill(Color.white)
                .overlay(Circle().stroke(laneColor, lineWidth: 1.5))
                .frame(width: 9, height: 9)
                .frame(width: 36, height: 36)   // hit target
                .contentShape(Rectangle())
                .position(x: x, y: y)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { g in
                            if curveDragIndex == nil {
                                curveDragIndex = i
                                curveDragStartValue = curve[i].value
                                UIHaptics.dragEvent()
                            }
                            var updated = curve
                            updated[i].value = Float(max(0, min(1, Double(curveDragStartValue) - Double(g.translation.height / height))))
                            onUpdateCurve?(event.id, updated)
                        }
                        .onEnded { _ in
                            curveDragIndex = nil
                            UIHaptics.dropEvent()
                        }
                )
        }
    }

    /// Filled waveform of an envelope-following continuous event's intensity
    /// curve. Baseline at the bottom of the bar, curve value = height.
    private func envelopeWaveform(curve: [HapticCurvePoint], duration: Double, laneColor: Color) -> some View {
        Canvas { context, size in
            guard duration > 0 else { return }
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height))
            for point in curve {
                let x = CGFloat(max(0, min(1, point.time / duration))) * size.width
                let y = size.height * (1 - CGFloat(max(0, min(1, point.value))))
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()

            context.fill(
                path,
                with: .linearGradient(
                    Gradient(colors: [laneColor.opacity(0.95), laneColor.opacity(0.55)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
        }
    }

    private func isEventActive(_ event: HapticEvent) -> Bool {
        let tolerance = 0.06
        if event.type == .continuous && event.duration > 0 {
            return currentTime >= event.time - tolerance && currentTime <= event.time + event.duration + tolerance
        }
        return abs(currentTime - event.time) < tolerance
    }

    // MARK: - Playhead (spans the entire stacked content)

    private var playhead: some View {
        let x = CGFloat(currentTime) * pixelsPerSecond

        return ZStack(alignment: .top) {
            // Vertical line
            Rectangle()
                .fill(EditorColors.playhead)
                .frame(width: 1.5)
                .offset(x: x)

            // Triangle handle on the ruler
            Triangle()
                .fill(EditorColors.playhead)
                .frame(width: 12, height: 10)
                .offset(x: x - 6, y: EditorDimensions.timeRulerHeight - 10)
        }
        .frame(
            width: max(contentWidth, 1),
            height: EditorDimensions.timeRulerHeight + EditorDimensions.videoTrackHeight + CGFloat(Self.trackOrder.count) * EditorDimensions.hapticTrackHeight,
            alignment: .topLeading
        )
        .allowsHitTesting(false)
        .animation(.linear(duration: isPlaying ? 0.05 : 0.0), value: currentTime)
    }

    // MARK: - Helpers

    /// Snap a time to the zoom-dependent grid: 0.1s zoomed out, 0.05s zoomed in.
    private func snappedTime(_ t: Double) -> Double {
        guard snapEnabled else { return t }
        let grid = zoomScale < 2 ? 0.1 : 0.05
        return (t / grid).rounded() * grid
    }

    private func formatTimeShort(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Triangle Shape

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.closeSubpath()
        }
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
                HapticEvent(time: 4.0, intensity: 0.7, sharpness: 0.6, duration: 0.5, type: .continuous),
                HapticEvent(time: 6.0, intensity: 0.9, sharpness: 0.4, duration: 2.0, type: .continuous,
                            intensityCurve: [
                                HapticCurvePoint(time: 0.0, value: 0.2),
                                HapticCurvePoint(time: 0.4, value: 0.9),
                                HapticCurvePoint(time: 0.8, value: 0.4),
                                HapticCurvePoint(time: 1.2, value: 1.0),
                                HapticCurvePoint(time: 1.6, value: 0.5),
                                HapticCurvePoint(time: 2.0, value: 0.1)
                            ])
            ]),
            currentTime: .constant(2.0),
            selectedEvent: .constant(nil),
            videoDuration: 10.0,
            zoomScale: 1.5,
            activeTool: .transient,
            isPlaying: true,
            thumbnails: [],
            onSeek: { _ in },
            onAddEvent: { _, _ in },
            onMoveEvent: { _, _ in },
            onDeleteEvent: { _ in },
            onSelectEvent: { _ in }
        )
        .frame(height: 220)
    }
}
