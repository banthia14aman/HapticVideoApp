//
//  AuthenticationViewModel.swift
//  HapticVideoApp
//

import Foundation
import Supabase

@MainActor
class AuthenticationViewModel: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var errorMessage: String?

    private var authListenerTask: Task<Void, Never>?

    init() {
        guard AppBackend.useCloud else {
            // Local mode: restore the on-device profile if one exists.
            currentUser = LocalDataStore.shared.loadUser()
            isAuthenticated = currentUser != nil
            return
        }
        // Skip network calls when running inside Xcode Preview sandbox
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == nil else {
            return
        }
        startAuthListener()
    }

    deinit {
        authListenerTask?.cancel()
    }

    // MARK: - Auth State Listener (cloud mode)

    private func startAuthListener() {
        // [weak self]: the for-await loop runs for the app's lifetime; a strong
        // capture would keep this view model alive forever.
        authListenerTask = Task { [weak self] in
            for await (event, session) in supabase.auth.authStateChanges {
                guard let self else { return }
                switch event {
                case .signedIn, .tokenRefreshed:
                    isAuthenticated = true
                    if let uid = session?.user.id.uuidString {
                        await fetchUserProfile(id: uid)
                    }
                case .signedOut:
                    isAuthenticated = false
                    currentUser = nil
                default:
                    break
                }
            }
        }
    }

    private func fetchUserProfile(id: String) async {
        do {
            let user: User = try await supabase
                .from("users")
                .select()
                .eq("id", value: id)
                .single()
                .execute()
                .value
            currentUser = user
        } catch {
            // Profile may not exist yet on first sign-up — not fatal
            print("ℹ️ User profile not found: \(error.localizedDescription)")
        }
    }

    // MARK: - Auth Actions

    func signUp(username: String, displayName: String, email: String, password: String) {
        guard !username.isEmpty, !displayName.isEmpty, !email.isEmpty, !password.isEmpty else {
            errorMessage = "All fields are required"
            return
        }

        guard AppBackend.useCloud else {
            signInLocally(username: username, displayName: displayName, email: email)
            return
        }

        Task {
            do {
                let response = try await supabase.auth.signUp(email: email, password: password)

                let appUser = User(
                    id: response.user.id.uuidString,
                    username: username,
                    displayName: displayName,
                    email: email
                )

                // Insert profile row — auth listener will set isAuthenticated
                try await supabase
                    .from("users")
                    .insert(appUser)
                    .execute()

                currentUser = appUser
                errorMessage = nil

            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func signIn(email: String, password: String) {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Email and password required"
            return
        }

        guard AppBackend.useCloud else {
            // Local mode: reuse the stored profile when the email matches,
            // otherwise mint one from the email. No real credential check —
            // there is nothing to authenticate against on-device.
            if let stored = LocalDataStore.shared.loadUser(), stored.email == email {
                signInLocally(user: stored)
            } else {
                let name = String(email.split(separator: "@").first ?? "user")
                signInLocally(username: name, displayName: name, email: email)
            }
            return
        }

        Task {
            do {
                try await supabase.auth.signIn(
                    email: email,
                    password: password
                )
                // Auth listener handles isAuthenticated + user fetch
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func signOut() {
        guard AppBackend.useCloud else {
            // Keep the on-device profile; just end the session.
            isAuthenticated = false
            return
        }

        Task {
            do {
                try await supabase.auth.signOut()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Local Mode Helpers

    /// The profile saved on-device, if any (local mode only).
    var savedLocalProfile: User? {
        guard !AppBackend.useCloud else { return nil }
        return currentUser ?? LocalDataStore.shared.loadUser()
    }

    /// Local-mode sign-up: display name + username only, no credentials.
    func createLocalProfile(displayName: String, username: String) {
        guard !displayName.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Display name is required"
            return
        }
        let name = username.lowercased()
        guard name.range(of: "^[a-z0-9_]{3,20}$", options: .regularExpression) != nil else {
            errorMessage = "Username must be 3–20 characters: letters, numbers, or underscores"
            return
        }
        // ponytail: email unused on-device, kept empty to satisfy the model
        signInLocally(user: User(username: name, displayName: displayName, email: ""))
    }

    /// Re-enter the saved on-device profile after a local sign-out.
    func continueLocalProfile() {
        guard let user = LocalDataStore.shared.loadUser() else { return }
        signInLocally(user: user)
    }

    /// Wipe the on-device profile entirely ("Start over").
    func deleteLocalProfile() {
        LocalDataStore.shared.clearUser()
        currentUser = nil
        isAuthenticated = false
    }

    private func signInLocally(username: String, displayName: String, email: String) {
        // Keep a stable identity per email so re-signing in owns prior uploads.
        let existing = LocalDataStore.shared.loadUser()
        let user = (existing?.email == email)
            ? existing!
            : User(username: username, displayName: displayName, email: email)
        signInLocally(user: user)
    }

    private func signInLocally(user: User) {
        LocalDataStore.shared.saveUserMetadata(user)
        currentUser = user
        isAuthenticated = true
        errorMessage = nil
    }
}
