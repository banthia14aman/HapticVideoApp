//
//  AppTheme.swift
//  HapticVideoApp
//
//  Global app theme with 2025 design trends: glassmorphism, gradients, haptic feedback
//

import SwiftUI
import UIKit

// MARK: - App Colors

struct AppColors {
    // Primary Palette
    static let primary = Color(hex: "FF2D55")
    static let primaryGradient = LinearGradient(
        colors: [Color(hex: "FF2D55"), Color(hex: "FF6B35")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // Backgrounds
    static let backgroundDark = Color(hex: "0A0A0A")
    static let backgroundPrimary = Color(hex: "121212")
    static let backgroundSecondary = Color(hex: "1C1C1E")
    static let backgroundTertiary = Color(hex: "2C2C2E")
    static let backgroundElevated = Color(hex: "3A3A3C")
    
    // Glass effect
    static let glassBackground = Color.white.opacity(0.08)
    static let glassBorder = Color.white.opacity(0.15)
    
    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "EBEBF5").opacity(0.6)
    static let textTertiary = Color(hex: "EBEBF5").opacity(0.3)
    
    // Accents
    static let success = Color(hex: "30D158")
    static let warning = Color(hex: "FFD60A")
    static let error = Color(hex: "FF453A")
    static let info = Color(hex: "5E5CE6")
    
    // Haptic Type Colors
    static let transient = Color(hex: "FF375F")
    static let impact = Color(hex: "5E5CE6")
    static let continuous = Color(hex: "30D158")
    
    // Gradients
    static let meshGradient = MeshGradient(
        width: 3, height: 3,
        points: [
            [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
            [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
            [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
        ],
        colors: [
            .purple.opacity(0.3), .pink.opacity(0.2), .orange.opacity(0.3),
            .blue.opacity(0.2), .purple.opacity(0.3), .pink.opacity(0.2),
            .cyan.opacity(0.3), .blue.opacity(0.2), .purple.opacity(0.3)
        ]
    )
    
    static let accentGradient = LinearGradient(
        colors: [Color(hex: "FF2D55"), Color(hex: "AF52DE")],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    static let darkGradient = LinearGradient(
        colors: [Color(hex: "1C1C1E"), Color(hex: "0A0A0A")],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - App Typography

struct AppTypography {
    static let largeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
    static let title = Font.system(size: 28, weight: .bold, design: .rounded)
    static let title2 = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let title3 = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let headline = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 17, weight: .regular)
    static let callout = Font.system(size: 16, weight: .regular)
    static let subheadline = Font.system(size: 15, weight: .regular)
    static let footnote = Font.system(size: 13, weight: .regular)
    static let caption = Font.system(size: 12, weight: .regular)
    static let caption2 = Font.system(size: 11, weight: .regular)
    
    // Monospaced
    static let mono = Font.system(size: 14, weight: .medium, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .medium, design: .monospaced)
}

// MARK: - Glass Card Modifier

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 20
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(AppColors.glassBorder, lineWidth: 1)
                    )
            )
    }
}

// MARK: - Primary Button Style

struct PrimaryButtonStyle: ButtonStyle {
    var isLoading: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)
            }
            configuration.label
        }
        .font(.system(size: 17, weight: .semibold))
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppColors.primaryGradient)
                .shadow(color: AppColors.primary.opacity(0.4), radius: configuration.isPressed ? 4 : 8, y: configuration.isPressed ? 2 : 4)
        )
        .scaleEffect(configuration.isPressed ? 0.98 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
        .opacity(isLoading ? 0.8 : 1)
        .onChange(of: configuration.isPressed) { _, isPressed in
            if isPressed {
                UIHaptics.buttonTapMedium()
            }
        }
    }
}

// MARK: - Secondary Button Style

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(AppColors.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppColors.primary.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppColors.primary.opacity(0.3), lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    UIHaptics.buttonTap()
                }
            }
    }
}

// MARK: - Floating Card Style

struct FloatingCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(AppColors.backgroundSecondary)
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            )
    }
}

// MARK: - Icon Button Style

struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 44
    var background: Color = AppColors.backgroundTertiary
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(configuration.isPressed ? background.opacity(0.5) : background)
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    UIHaptics.buttonTap()
                }
            }
    }
}

// MARK: - Modern Text Field

struct ModernTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(isFocused ? AppColors.primary : AppColors.textTertiary)
                .frame(width: 24)
            
            if isSecure {
                SecureField(placeholder, text: $text)
                    .focused($isFocused)
            } else {
                TextField(placeholder, text: $text)
                    .focused($isFocused)
            }
        }
        .font(.system(size: 17))
        .foregroundColor(AppColors.textPrimary)
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppColors.backgroundTertiary)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isFocused ? AppColors.primary : Color.clear, lineWidth: 2)
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

// MARK: - Shimmer Effect

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.2),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + (geometry.size.width * 2 * phase))
                }
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

// MARK: - View Extensions

extension View {
    func glassCard(cornerRadius: CGFloat = 20, padding: CGFloat = 20) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, padding: padding))
    }
    
    func floatingCard() -> some View {
        modifier(FloatingCard())
    }
    
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}
