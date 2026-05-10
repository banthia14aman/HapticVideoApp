//
//  HapticVideoAppApp.swift
//  HapticVideoApp
//

import SwiftUI

@main
struct HapticVideoAppApp: App {
    @StateObject private var authViewModel = AuthenticationViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
        }
    }
}
