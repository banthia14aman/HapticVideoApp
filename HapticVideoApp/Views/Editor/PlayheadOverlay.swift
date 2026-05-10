//
//  PlayheadOverlay.swift
//  HapticVideoApp
//
//  Created by Aman Banthia on 13/12/25.
//


//
//  PlayheadOverlay.swift
//  HapticVideoApp
//

import SwiftUI

struct PlayheadOverlay: View {
    let contentWidth: CGFloat
    let laneHeight: CGFloat
    let totalLength: Double
    @Binding var playhead: Double
    var onScrub: (Double) -> Void
    
    var body: some View {
        let x = xForTime(playhead)
        
        ZStack {
            // Playhead line (non-interactive)
            Rectangle()
                .fill(Color.red.opacity(0.9))
                .frame(width: 2, height: laneHeight)
                .position(x: x, y: laneHeight / 2)
                .allowsHitTesting(false)
            
            // Top draggable circle
            Circle()
                .fill(Color.red)
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.3), radius: 2)
                .position(x: x, y: 12)
                .gesture(scrubGesture)
            
            // Bottom draggable circle
            Circle()
                .fill(Color.red)
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.3), radius: 2)
                .position(x: x, y: laneHeight - 12)
                .gesture(scrubGesture)
            
            // Time display
            Text(timeString(playhead))
                .font(.caption2)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red)
                .cornerRadius(4)
                .position(x: max(30, min(contentWidth - 30, x)), y: laneHeight - 25)
                .allowsHitTesting(false)
        }
        .frame(width: contentWidth, height: laneHeight)
    }
    
    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let newTime = timeForX(value.location.x)
                playhead = max(0, min(totalLength, newTime))
            }
            .onEnded { value in
                let finalTime = timeForX(value.location.x)
                onScrub(max(0, min(totalLength, finalTime)))
            }
    }
    
    private func xForTime(_ time: Double) -> CGFloat {
        CGFloat(max(0, min(1, time / totalLength))) * contentWidth
    }
    
    private func timeForX(_ x: CGFloat) -> Double {
        Double(max(0, min(1, x / contentWidth))) * totalLength
    }
    
    private func timeString(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let centiseconds = Int((time - Double(Int(time))) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, centiseconds)
    }
}
