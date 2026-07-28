//
//  ContentView.swift
//  HapticVideoApp
//
//  Modern 2025 main view with floating tab bar
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        Group {
            if !hasOnboarded {
                OnboardingView(onComplete: { hasOnboarded = true })
            } else if authViewModel.isAuthenticated {
                MainTabView()
            } else {
                AuthenticationView()
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Modern Tab Bar

struct MainTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab Content
            TabView(selection: $selectedTab) {
                FeedView()
                    .tag(0)
                
                UploadView()
                    .tag(1)
                
                ProfileView()
                    .tag(2)
            }
            
            // Custom Floating Tab Bar
            floatingTabBar
                .padding(.horizontal, 60)
                .padding(.bottom, 20)
        }
        .ignoresSafeArea(.keyboard)
        // ponytail: single haptic source for tab switches (buttons, swipes) — buttons don't fire their own
        .onChange(of: selectedTab) { _, _ in
            UIHaptics.selectionChanged()
        }
    }
    
    private var floatingTabBar: some View {
        HStack(spacing: 0) {
            TabBarButton(
                icon: "play.rectangle.fill",
                title: "Feed",
                isSelected: selectedTab == 0
            ) {
                withAnimation(.spring(response: 0.3)) {
                    selectedTab = 0
                }
            }
            
            Spacer()
            
            // Center Upload Button
            Button {
                withAnimation(.spring(response: 0.3)) {
                    selectedTab = 1
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(AppColors.primaryGradient)
                        .frame(width: 56, height: 56)
                        .shadow(color: AppColors.primary.opacity(0.5), radius: 10, y: 5)
                    
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .offset(y: -16)
            
            Spacer()
            
            TabBarButton(
                icon: "person.fill",
                title: "Profile",
                isSelected: selectedTab == 2
            ) {
                withAnimation(.spring(response: 0.3)) {
                    selectedTab = 2
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        )
    }
}

// MARK: - Tab Bar Button

struct TabBarButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? AppColors.primary : AppColors.textSecondary)
                
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? AppColors.primary : AppColors.textSecondary)
            }
            .frame(width: 60)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthenticationViewModel())
}
