//
//  AuthenticationViewModel.swift
//  HapticVideoApp
//

import Foundation
import FirebaseAuth

@MainActor
class AuthenticationViewModel: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var errorMessage: String?
    
    // Note: Requires Firebase SDK
    
    init() {
        checkAuthenticationStatus()
    }
    
    private func checkAuthenticationStatus() {
        if let authUser = Auth.auth().currentUser {
            // Mocking the user metadata load for now, usually you fetch from Firestore
            self.currentUser = User(id: authUser.uid, username: authUser.displayName ?? "User", displayName: authUser.displayName ?? "User", email: authUser.email ?? "")
            self.isAuthenticated = true
        } else {
            self.isAuthenticated = false
        }
    }
    
    func signUp(username: String, displayName: String, email: String, password: String) {
        guard !username.isEmpty, !displayName.isEmpty, !email.isEmpty, !password.isEmpty else {
            errorMessage = "All fields are required"
            return
        }
        
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] authResult, error in
            guard let self = self else { return }
            
            if let error = error {
                self.errorMessage = error.localizedDescription
                return
            }
            
            if let user = authResult?.user {
                let appUser = User(id: user.uid, username: username, displayName: displayName, email: email)
                CloudDataStore.shared.saveUserMetadata(appUser)
                
                DispatchQueue.main.async {
                    self.currentUser = appUser
                    self.isAuthenticated = true
                    self.errorMessage = nil
                }
            }
        }
    }
    
    func signIn(email: String, password: String) {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Email and password required"
            return
        }
        
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] authResult, error in
            guard let self = self else { return }
            
            if let error = error {
                self.errorMessage = error.localizedDescription
                return
            }
            
            if let user = authResult?.user {
                // Ideally fetch full user profile from Firestore here
                DispatchQueue.main.async {
                    self.currentUser = User(id: user.uid, username: user.displayName ?? "User", displayName: user.displayName ?? "User", email: email)
                    self.isAuthenticated = true
                    self.errorMessage = nil
                }
            }
        }
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            self.currentUser = nil
            self.isAuthenticated = false
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
