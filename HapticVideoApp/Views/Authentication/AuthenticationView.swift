//
//  AuthenticationView.swift
//  HapticVideoApp
//
//  Modern 2025 authentication UI with glassmorphism and haptic feedback
//

import SwiftUI

struct AuthenticationView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var displayName = ""
    @State private var isSignUp = false
    @State private var isLoading = false
    @State private var showError = false
    @State private var animateGradient = false
    
    var body: some View {
        ZStack {
            // Animated Background
            animatedBackground
            
            // Content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    Spacer()
                        .frame(height: 60)
                    
                    // Logo & Branding
                    brandingSection
                    
                    // Auth Card
                    authCard
                        .padding(.horizontal, 24)
                    
                    // Toggle Auth Mode
                    toggleAuthMode
                    
                    Spacer()
                        .frame(height: 40)
                }
            }
        }
        .preferredColorScheme(.dark)
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(authViewModel.errorMessage ?? "Something went wrong")
        }
        .onAppear {
            UIHaptics.prepare()
        }
    }
    
    // MARK: - Animated Background
    
    private var animatedBackground: some View {
        ZStack {
            AppColors.backgroundDark
                .ignoresSafeArea()
            
            // Mesh gradient effect
            GeometryReader { geometry in
                ZStack {
                    // Top blob
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [AppColors.primary.opacity(0.4), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 300
                            )
                        )
                        .frame(width: 400, height: 400)
                        .offset(x: animateGradient ? 50 : -50, y: -200)
                        .blur(radius: 80)
                    
                    // Bottom blob
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.purple.opacity(0.3), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 250
                            )
                        )
                        .frame(width: 350, height: 350)
                        .offset(x: animateGradient ? -30 : 30, y: geometry.size.height - 300)
                        .blur(radius: 60)
                    
                    // Accent blob
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.blue.opacity(0.25), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 200
                            )
                        )
                        .frame(width: 300, height: 300)
                        .offset(x: geometry.size.width - 150, y: geometry.size.height / 2)
                        .blur(radius: 70)
                }
            }
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                    animateGradient = true
                }
            }
        }
    }
    
    // MARK: - Branding Section
    
    private var brandingSection: some View {
        VStack(spacing: 16) {
            // App Icon
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(AppColors.primaryGradient)
                    .frame(width: 80, height: 80)
                    .shadow(color: AppColors.primary.opacity(0.5), radius: 20, y: 10)
                
                Image(systemName: "waveform.path")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(.white)
            }
            
            // App Name
            VStack(spacing: 8) {
                Text("HapticVideo")
                    .font(AppTypography.largeTitle)
                    .foregroundColor(AppColors.textPrimary)
                
                Text("Feel your content")
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }
    
    // MARK: - Auth Card
    
    private var authCard: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text(isSignUp ? "Create Account" : "Welcome Back")
                    .font(AppTypography.title2)
                    .foregroundColor(AppColors.textPrimary)
                
                Text(isSignUp ? "Sign up to get started" : "Sign in to continue")
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColors.textSecondary)
            }
            
            // Form Fields
            VStack(spacing: 16) {
                if isSignUp {
                    ModernTextField(
                        icon: "person.fill",
                        placeholder: "Username",
                        text: $username
                    )
                    .textInputAutocapitalization(.never)
                    
                    ModernTextField(
                        icon: "person.text.rectangle.fill",
                        placeholder: "Display Name",
                        text: $displayName
                    )
                }
                
                ModernTextField(
                    icon: "envelope.fill",
                    placeholder: "Email",
                    text: $email
                )
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                
                ModernTextField(
                    icon: "lock.fill",
                    placeholder: "Password",
                    text: $password,
                    isSecure: true
                )
            }
            
            // Submit Button
            Button {
                performAuth()
            } label: {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    Text(isSignUp ? "Create Account" : "Sign In")
                }
            }
            .buttonStyle(PrimaryButtonStyle(isLoading: isLoading))
            .disabled(isLoading || !isFormValid)
            .opacity(isFormValid ? 1 : 0.6)
            
            // Demo Account
            if !isSignUp {
                Button {
                    UIHaptics.buttonTap()
                    email = "demo@hapticvideo.app"
                    password = "demo123"
                } label: {
                    Text("Use Demo Account")
                        .font(AppTypography.footnote)
                        .foregroundColor(AppColors.textSecondary)
                        .underline()
                }
            }
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(AppColors.glassBorder, lineWidth: 1)
                )
        )
    }
    
    // MARK: - Toggle Auth Mode
    
    private var toggleAuthMode: some View {
        HStack(spacing: 4) {
            Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                .font(AppTypography.footnote)
                .foregroundColor(AppColors.textSecondary)
            
            Button {
                UIHaptics.buttonTap()
                withAnimation(.spring(response: 0.3)) {
                    isSignUp.toggle()
                    // Clear fields
                    username = ""
                    displayName = ""
                }
            } label: {
                Text(isSignUp ? "Sign In" : "Sign Up")
                    .font(AppTypography.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.primary)
            }
        }
    }
    
    // MARK: - Helpers
    
    private var isFormValid: Bool {
        if isSignUp {
            return !email.isEmpty && !password.isEmpty && !username.isEmpty && !displayName.isEmpty
        }
        return !email.isEmpty && !password.isEmpty
    }
    
    private func performAuth() {
        UIHaptics.buttonTapMedium()
        isLoading = true
        
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if isSignUp {
                authViewModel.signUp(
                    username: username,
                    displayName: displayName,
                    email: email,
                    password: password
                )
            } else {
                authViewModel.signIn(email: email, password: password)
            }
            
            isLoading = false
            
            if authViewModel.isAuthenticated {
                UIHaptics.success()
            } else if authViewModel.errorMessage != nil {
                UIHaptics.error()
                showError = true
            }
        }
    }
}

#Preview {
    AuthenticationView()
        .environmentObject(AuthenticationViewModel())
}
