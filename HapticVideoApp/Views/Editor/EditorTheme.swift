//
//  EditorTheme.swift
//  HapticVideoApp
//
//  Design tokens and haptic UI feedback for professional DAW-style editor
//

import SwiftUI
import UIKit

// MARK: - Editor Colors

struct EditorColors {
    // Backgrounds
    static let background = Color(hex: "0D0D0D")
    static let trackBackground = Color(hex: "1A1A1A")
    static let surfaceElevated = Color(hex: "2A2A2A")
    static let surfaceHover = Color(hex: "3A3A3A")
    
    // Accent Colors
    static let accent = Color(hex: "FF2D55")
    static let playhead = Color(hex: "FF2D55")
    
    // Event Type Colors
    static let transient = Color(hex: "FF375F")
    static let impact = Color(hex: "5E5CE6")
    static let continuous = Color(hex: "30D158")
    
    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "8E8E93")
    static let textTertiary = Color(hex: "636366")
    
    // Timeline
    static let gridLine = Color.white.opacity(0.1)
    static let gridLineMajor = Color.white.opacity(0.25)
    static let timeRuler = Color(hex: "2C2C2E")
    
    // Event type color helper
    static func color(for type: HapticEventType) -> Color {
        switch type {
        case .transient: return transient
        case .impact: return impact
        case .continuous: return continuous
        }
    }
}

// MARK: - Hex Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - UI Haptic Feedback

struct UIHaptics {
    
    // MARK: - Standard Feedback Generators
    
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private static let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private static let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()
    
    // MARK: - Prepare (call before expected interaction)
    
    static func prepare() {
        lightImpact.prepare()
        mediumImpact.prepare()
        selection.prepare()
    }
    
    // MARK: - Button Interactions
    
    /// Light tap for standard buttons
    static func buttonTap() {
        lightImpact.impactOccurred()
    }
    
    /// Medium tap for important buttons (play, save)
    static func buttonTapMedium() {
        mediumImpact.impactOccurred()
    }
    
    /// Heavy tap for destructive actions
    static func buttonTapHeavy() {
        heavyImpact.impactOccurred()
    }
    
    // MARK: - Transport Controls
    
    /// Play button press
    static func play() {
        mediumImpact.impactOccurred(intensity: 0.8)
    }
    
    /// Pause button press
    static func pause() {
        softImpact.impactOccurred(intensity: 0.6)
    }
    
    /// Stop button press
    static func stop() {
        rigidImpact.impactOccurred(intensity: 0.7)
    }
    
    // MARK: - Timeline Interactions
    
    /// Selection changed (scrubbing, slider stepping)
    static func selectionChanged() {
        selection.selectionChanged()
    }
    
    /// Scrub haptic with intensity based on speed
    static func scrub(intensity: CGFloat = 0.5) {
        lightImpact.impactOccurred(intensity: min(1.0, max(0.2, intensity)))
    }
    
    /// Snap to grid
    static func snap() {
        rigidImpact.impactOccurred(intensity: 0.5)
    }
    
    // MARK: - Event Editing
    
    /// Add new event
    static func addEvent() {
        rigidImpact.impactOccurred(intensity: 0.8)
    }
    
    /// Delete event
    static func deleteEvent() {
        notification.notificationOccurred(.warning)
    }
    
    /// Select event
    static func selectEvent() {
        lightImpact.impactOccurred(intensity: 0.6)
    }
    
    /// Drag event
    static func dragEvent() {
        softImpact.impactOccurred(intensity: 0.3)
    }
    
    /// Drop event
    static func dropEvent() {
        mediumImpact.impactOccurred(intensity: 0.7)
    }
    
    // MARK: - Zoom
    
    /// Zoom in/out step
    static func zoom() {
        lightImpact.impactOccurred(intensity: 0.4)
    }
    
    // MARK: - Notifications
    
    /// Success feedback
    static func success() {
        notification.notificationOccurred(.success)
    }
    
    /// Error feedback
    static func error() {
        notification.notificationOccurred(.error)
    }
    
    /// Warning feedback
    static func warning() {
        notification.notificationOccurred(.warning)
    }
    
    // MARK: - Event Type Preview
    
    /// Preview haptic based on event type
    static func previewEventType(_ type: HapticEventType) {
        switch type {
        case .transient:
            rigidImpact.impactOccurred(intensity: 1.0)
        case .impact:
            heavyImpact.impactOccurred(intensity: 0.9)
        case .continuous:
            // Multiple soft taps to simulate continuous
            softImpact.impactOccurred(intensity: 0.6)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                softImpact.impactOccurred(intensity: 0.5)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                softImpact.impactOccurred(intensity: 0.4)
            }
        }
    }
}

// MARK: - Editor Dimensions

struct EditorDimensions {
    static let transportHeight: CGFloat = 60
    static let timelineHeight: CGFloat = 120
    static let timeRulerHeight: CGFloat = 24
    static let eventLaneHeight: CGFloat = 80
    static let inspectorHeight: CGFloat = 200
    
    static let eventMarkerSize: CGFloat = 16
    static let playheadWidth: CGFloat = 2
    static let gridSpacing: CGFloat = 50 // pixels per second at 1x zoom
    
    static let cornerRadius: CGFloat = 12
    static let buttonSize: CGFloat = 44
}

// MARK: - View Modifiers

struct EditorCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(EditorColors.surfaceElevated)
            .cornerRadius(EditorDimensions.cornerRadius)
    }
}

struct EditorButtonStyle: ButtonStyle {
    let isActive: Bool
    
    init(isActive: Bool = false) {
        self.isActive = isActive
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: EditorDimensions.buttonSize, height: EditorDimensions.buttonSize)
            .background(
                configuration.isPressed ? EditorColors.surfaceHover :
                isActive ? EditorColors.accent.opacity(0.2) :
                EditorColors.surfaceElevated
            )
            .foregroundColor(isActive ? EditorColors.accent : EditorColors.textPrimary)
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    UIHaptics.buttonTap()
                }
            }
    }
}

struct TransportButtonStyle: ButtonStyle {
    let isPlaying: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 56, height: 56)
            .background(
                Circle()
                    .fill(isPlaying ? EditorColors.accent : EditorColors.surfaceElevated)
            )
            .foregroundColor(isPlaying ? .white : EditorColors.textPrimary)
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension View {
    func editorCard() -> some View {
        modifier(EditorCardStyle())
    }
}
