//
//  EditorTheme.swift
//  HapticVideoApp
//
//  Premiere Pro-inspired design tokens for the mobile haptic editor.
//

import SwiftUI
import UIKit

// MARK: - Editor Colors (Premiere Pro Mobile palette)

struct EditorColors {
    // Backgrounds — layered dark grays like Premiere's panels
    static let background        = Color(hex: "121315")   // app chrome
    static let panel             = Color(hex: "1A1B1E")   // monitor/tools chrome
    static let trackBackground   = Color(hex: "232428")   // timeline lane background
    static let trackHeader       = Color(hex: "1E1F22")   // sticky lane label column
    static let surfaceElevated   = Color(hex: "2C2D31")   // buttons, chips
    static let surfaceHover      = Color(hex: "3A3B40")   // hover/pressed
    static let divider           = Color.white.opacity(0.06)

    // Premiere accent — that signature purple/violet
    static let accent            = Color(hex: "8C5CFF")
    static let accentMuted       = Color(hex: "8C5CFF").opacity(0.2)
    static let accentDeep        = Color(hex: "5B3FCC")
    static let playhead          = Color(hex: "F26A6A")   // signature red playhead

    // Event Type Colors — calmer, more pro-app feel
    static let transient         = Color(hex: "FF8A4C")   // warm orange
    static let impact            = Color(hex: "5BC0FF")   // cyan
    static let continuous        = Color(hex: "8C5CFF")   // violet

    // Text
    static let textPrimary       = Color(hex: "EDEDF0")
    static let textSecondary     = Color(hex: "9A9BA1")
    static let textTertiary      = Color(hex: "6B6C72")

    // Timeline grid
    static let gridLineMinor     = Color.white.opacity(0.04)
    static let gridLineMajor     = Color.white.opacity(0.12)
    static let timeRuler         = Color(hex: "1E1F22")
    static let trackSeparator    = Color.black.opacity(0.5)

    // Audio waveform
    static let waveform          = Color(hex: "4A5560")

    static func color(for type: HapticEventType) -> Color {
        switch type {
        case .transient:  return transient
        case .impact:     return impact
        case .continuous: return continuous
        }
    }

    static func icon(for type: HapticEventType) -> String {
        switch type {
        case .transient:  return "circle.fill"
        case .impact:     return "diamond.fill"
        case .continuous: return "rectangle.fill"
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
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

// MARK: - Editor Dimensions

struct EditorDimensions {
    static let topBarHeight: CGFloat        = 48
    static let transportHeight: CGFloat     = 56
    static let toolbarHeight: CGFloat       = 48
    static let timeRulerHeight: CGFloat     = 22
    static let videoTrackHeight: CGFloat    = 40
    static let hapticTrackHeight: CGFloat   = 44
    static let trackHeaderWidth: CGFloat    = 64
    static let inspectorHeight: CGFloat     = 220
    static let basePixelsPerSecond: CGFloat = 80
}

// MARK: - UI Haptic Feedback

struct UIHaptics {
    private static let lightImpact   = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact  = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyImpact   = UIImpactFeedbackGenerator(style: .heavy)
    private static let rigidImpact   = UIImpactFeedbackGenerator(style: .rigid)
    private static let softImpact    = UIImpactFeedbackGenerator(style: .soft)
    private static let selection     = UISelectionFeedbackGenerator()
    private static let notification  = UINotificationFeedbackGenerator()

    static func prepare() {
        lightImpact.prepare()
        mediumImpact.prepare()
        selection.prepare()
    }

    static func buttonTap()         { lightImpact.impactOccurred() }
    static func buttonTapMedium()   { mediumImpact.impactOccurred() }
    static func buttonTapHeavy()    { heavyImpact.impactOccurred() }
    static func play()              { mediumImpact.impactOccurred(intensity: 0.8) }
    static func pause()             { softImpact.impactOccurred(intensity: 0.6) }
    static func stop()              { rigidImpact.impactOccurred(intensity: 0.7) }
    static func selectionChanged()  { selection.selectionChanged() }
    static func scrub(intensity: CGFloat = 0.5) {
        lightImpact.impactOccurred(intensity: min(1.0, max(0.2, intensity)))
    }
    static func snap()              { rigidImpact.impactOccurred(intensity: 0.5) }
    static func addEvent()          { rigidImpact.impactOccurred(intensity: 0.8) }
    static func deleteEvent()       { notification.notificationOccurred(.warning) }
    static func selectEvent()       { lightImpact.impactOccurred(intensity: 0.6) }
    static func dragEvent()         { softImpact.impactOccurred(intensity: 0.3) }
    static func dropEvent()         { mediumImpact.impactOccurred(intensity: 0.7) }
    static func zoom()              { lightImpact.impactOccurred(intensity: 0.4) }
    static func success()           { notification.notificationOccurred(.success) }
    static func error()             { notification.notificationOccurred(.error) }
    static func warning()           { notification.notificationOccurred(.warning) }

    static func previewEventType(_ type: HapticEventType) {
        switch type {
        case .transient:
            rigidImpact.impactOccurred(intensity: 1.0)
        case .impact:
            heavyImpact.impactOccurred(intensity: 0.9)
        case .continuous:
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

// MARK: - Editor Tool

enum EditorTool: String, CaseIterable, Identifiable {
    case select
    case transient
    case impact
    case continuous

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .select:     return "cursorarrow"
        case .transient:  return "circle.fill"
        case .impact:     return "diamond.fill"
        case .continuous: return "rectangle.fill"
        }
    }

    var label: String {
        switch self {
        case .select:     return "Select"
        case .transient:  return "Tap"
        case .impact:     return "Beat"
        case .continuous: return "Hold"
        }
    }

    var eventType: HapticEventType? {
        switch self {
        case .select:     return nil
        case .transient:  return .transient
        case .impact:     return .impact
        case .continuous: return .continuous
        }
    }

    var color: Color {
        switch self {
        case .select:     return EditorColors.accent
        case .transient:  return EditorColors.transient
        case .impact:     return EditorColors.impact
        case .continuous: return EditorColors.continuous
        }
    }
}

// MARK: - Premiere-style Button

struct PremiereChipStyle: ButtonStyle {
    let isActive: Bool
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(isActive ? .white : EditorColors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? tint : EditorColors.surfaceElevated)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
