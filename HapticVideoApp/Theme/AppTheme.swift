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
    
    // Glass effect
    static let glassBackground = Color.white.opacity(0.08)
    static let glassBorder = Color.white.opacity(0.15)
    
    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "EBEBF5").opacity(0.6)
    static let textTertiary = Color(hex: "EBEBF5").opacity(0.45) // was 0.3 (~2.1:1 on backgroundDark); 0.45 ≈ 4:1

    // Accents
    static let success = Color(hex: "30D158")
    static let warning = Color(hex: "FFD60A")
    static let error = Color(hex: "FF453A")
    static let info = Color(hex: "5E5CE6")
    static let demoBadge = Color(hex: "FFD60A") // DEMO badge accent
    
    // Haptic Type Colors
    static let transient = Color(hex: "FF375F")
    static let impact = Color(hex: "5E5CE6")
    static let continuous = Color(hex: "30D158")
    
}

// MARK: - App Typography

struct AppTypography {
    // Text styles scale with Dynamic Type; default sizes match the old fixed values.
    static let largeTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let title = Font.system(.title, design: .rounded).weight(.bold)
    static let title2 = Font.system(.title2, design: .rounded).weight(.semibold)
    static let title3 = Font.system(.title3, design: .rounded).weight(.semibold)
    static let headline = Font.system(.body).weight(.semibold)
    static let body = Font.system(.body)
    static let callout = Font.system(.callout)
    static let subheadline = Font.system(.subheadline)
    static let footnote = Font.system(.footnote)
    static let caption = Font.system(.caption)
    static let caption2 = Font.system(.caption2)

    // Monospaced (was fixed 14pt; .footnote = 13pt default, closest scaling style)
    static let mono = Font.system(.footnote, design: .monospaced).weight(.medium)
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
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}
