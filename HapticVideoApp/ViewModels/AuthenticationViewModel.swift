//
//  AuthenticationViewModel.swift
//  HapticVideoApp
//

import Foundation

@MainActor
class AuthenticationViewModel: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var errorMessage: String?
    
    private let dataStore = LocalDataStore.shared
    
    init() {
        checkAuthenticationStatus()
    }
    
    private func checkAuthenticationStatus() {
        if let user = dataStore.getCurrentUser() {
            currentUser = user
            isAuthenticated = true
            print("✅ User logged in: \(user.username)")
        }
    }
    
    func signUp(username: String, displayName: String, email: String, password: String) {
        guard !username.isEmpty, !displayName.isEmpty, !email.isEmpty, !password.isEmpty else {
            errorMessage = "All fields are required"
            return
        }
        
        let user = User(
            username: username,
            displayName: displayName,
            email: email
        )
        
        dataStore.saveUser(user)
        currentUser = user
        isAuthenticated = true
        errorMessage = nil
        
        print("✅ User signed up: \(username)")
    }
    
    func signIn(email: String, password: String) {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Email and password required"
            return
        }
        
        if let existingUser = dataStore.getCurrentUser() {
            if existingUser.email == email {
                currentUser = existingUser
                isAuthenticated = true
                errorMessage = nil
                print("✅ User signed in: \(existingUser.username)")
                return
            }
        }
        
        // Demo: auto-create user
        let user = User(
            username: email.components(separatedBy: "@").first ?? "user",
            displayName: "User",
            email: email
        )
        dataStore.saveUser(user)
        currentUser = user
        isAuthenticated = true
        errorMessage = nil
    }
    
    func signOut() {
        dataStore.clearCurrentUser()
        currentUser = nil
        isAuthenticated = false
        print("👋 Signed out")
    }
}
