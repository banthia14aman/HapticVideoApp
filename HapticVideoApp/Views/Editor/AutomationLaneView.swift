//
//  AutomationLaneView.swift
//  HapticVideoApp
//
//  Created by Aman Banthia on 13/12/25.
//


//
//  AutomationLaneView.swift
//  HapticVideoApp
//

import SwiftUI

struct AutomationLaneView: View {
    let title: String
    let color: Color
    @Binding var points: [CurvePoint]
    @Binding var currentTime: Double
    let videoDuration: Double
    let zoomScale: Double
    var onSeek: (Double) -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background grid
                gridBackground(size: geometry.size)
                
                // Curve path
                if points.count >= 2 {
                    curvePath(in: geometry.size)
                        .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
                
                // Control points
                ForEach(points) { point in
                    let pos = pointToPosition(point, in: geometry.size)
                    Circle()
                        .fill(color)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .position(pos)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    dragPoint(point.id, to: value.location, size: geometry.size)
                                }
                        )
                        .onTapGesture {
                            withAnimation {
                                points.removeAll { $0.id == point.id }
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
                addPoint(at: location, size: geometry.size)
            }
        }
    }
    
    private func gridBackground(size: CGSize) -> some View {
        Canvas { ctx, canvasSize in
            // Horizontal lines (0.0, 0.5, 1.0)
            for i in 0...2 {
                let y = CGFloat(i) * canvasSize.height / 2
                ctx.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: canvasSize.width, y: y))
                    },
                    with: .color(.gray.opacity(i == 1 ? 0.4 : 0.2)),
                    lineWidth: 1
                )
            }
            
            // Vertical time markers
            let secondWidth = canvasSize.width / CGFloat(videoDuration)
            for i in 0...Int(videoDuration) {
                let x = CGFloat(i) * secondWidth
                ctx.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                    },
                    with: .color(.gray.opacity(0.15)),
                    lineWidth: 1
                )
            }
        }
        .background(Color.black.opacity(0.04))
        .cornerRadius(8)
    }
    
    private func curvePath(in size: CGSize) -> Path {
        var path = Path()
        let sorted = points.sorted { $0.time < $1.time }
        
        guard let first = sorted.first else { return path }
        path.move(to: pointToPosition(first, in: size))
        
        for point in sorted.dropFirst() {
            path.addLine(to: pointToPosition(point, in: size))
        }
        
        return path
    }
    
    private func addPoint(at location: CGPoint, size: CGSize) {
        let time = Double(location.x / size.width) * videoDuration
        let value = Float(max(0, min(1, 1.0 - location.y / size.height)))
        
        withAnimation {
            points.append(CurvePoint(time: time, value: value))
        }
    }
    
    private func dragPoint(_ id: UUID, to location: CGPoint, size: CGSize) {
        let time = max(0, min(videoDuration, Double(location.x / size.width) * videoDuration))
        let value = Float(max(0, min(1, 1.0 - location.y / size.height)))
        
        if let index = points.firstIndex(where: { $0.id == id }) {
            points[index].time = time
            points[index].value = value
        }
    }
    
    private func pointToPosition(_ point: CurvePoint, in size: CGSize) -> CGPoint {
        let x = CGFloat(point.time / videoDuration) * size.width
        let y = (1 - CGFloat(point.value)) * size.height
        return CGPoint(x: x, y: y)
    }
}
