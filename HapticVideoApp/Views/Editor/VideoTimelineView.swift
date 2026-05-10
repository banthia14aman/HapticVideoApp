//
//  VideoTimelineView 2.swift
//  HapticVideoApp
//
//  Created by Aman Banthia on 13/12/25.
//


//
//  VideoTimelineView.swift
//  HapticVideoApp
//

import SwiftUI

struct VideoTimelineView: View {
    @Binding var events: [HapticEvent]
    @Binding var currentTime: Double
    let videoDuration: Double
    let zoomScale: Double
    let selectedEventType: HapticEventType
    var onSeek: (Double) -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background grid
                gridBackground(size: geometry.size)
                
                // Events
                ForEach(events) { event in
                    eventGlyph(event, in: geometry.size)
                        .onLongPressGesture {
                            withAnimation {
                                events.removeAll { $0.id == event.id }
                            }
                        }
                }
                
                // Playhead overlay
                PlayheadOverlay(
                    contentWidth: geometry.size.width,
                    laneHeight: geometry.size.height,
                    totalLength: videoDuration,
                    playhead: $currentTime,
                    onScrub: onSeek
                )
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                addEvent(at: location, size: geometry.size)
            }
        }
    }
    
    private func gridBackground(size: CGSize) -> some View {
        Canvas { ctx, canvasSize in
            // Draw time markers every second
            let secondWidth = canvasSize.width / CGFloat(videoDuration)
            
            for i in 0...Int(videoDuration) {
                let x = CGFloat(i) * secondWidth
                let isWhole = i % 5 == 0
                
                ctx.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                    },
                    with: .color(.gray.opacity(isWhole ? 0.4 : 0.15)),
                    lineWidth: isWhole ? 2 : 1
                )
            }
        }
        .background(Color.black.opacity(0.04))
        .cornerRadius(8)
    }
    
    private func eventGlyph(_ event: HapticEvent, in size: CGSize) -> some View {
        let x = timeToPosition(event.time, width: size.width)
        
        return Group {
            if event.type == .transient {
                Circle()
                    .fill(Color.pink)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .position(x: x, y: size.height / 2)
            } else if event.type == .impact {
                Diamond()
                    .fill(Color.blue)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Diamond()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .position(x: x, y: size.height / 2)
            } else {
                let width = max(20, timeToPosition(event.duration, width: size.width))
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.green.opacity(0.7))
                    .frame(width: width, height: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .position(x: x + width / 2, y: size.height / 2)
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 2)
    }
    
    private func addEvent(at location: CGPoint, size: CGSize) {
        let time = positionToTime(location.x, width: size.width)
        
        let newEvent = HapticEvent(
            time: time,
            intensity: 0.7,
            sharpness: 0.5,
            duration: selectedEventType == .continuous ? 0.3 : 0.0,
            type: selectedEventType
        )
        
        withAnimation {
            events.append(newEvent)
            events.sort { $0.time < $1.time }
        }
    }
    
    private func timeToPosition(_ time: Double, width: CGFloat) -> CGFloat {
        CGFloat(time / videoDuration) * width
    }
    
    private func positionToTime(_ x: CGFloat, width: CGFloat) -> Double {
        max(0, min(videoDuration, Double(x / width) * videoDuration))
    }
}

struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
        }
    }
}
