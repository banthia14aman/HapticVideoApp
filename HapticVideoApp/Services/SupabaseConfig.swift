//
//  SupabaseConfig.swift
//  HapticVideoApp
//
//  Supabase client configuration.
//  Replace the placeholder values below with your actual project credentials.
//  Dashboard → Settings → API → Project URL & anon/public key.
//

import Foundation
import Supabase

// MARK: - Credentials (fill these in)

private enum SupabaseCredentials {
    static let projectURL = URL(string: "https://wcrjhrhkeaavdlnahzyo.supabase.co")!
    static let anonKey    = "sb_publishable_SAK9pKw3bTnX6ilDPTIFRQ_A39wS3W3"
}

// MARK: - Shared client

/// Single Supabase client used throughout the app.
/// Accessing this before setting real credentials is safe — it won't crash,
/// but all network calls will fail until the credentials are correct.
let supabase = SupabaseClient(
    supabaseURL: SupabaseCredentials.projectURL,
    supabaseKey: SupabaseCredentials.anonKey
)
