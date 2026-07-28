//
//  ABTestStore.swift
//  HapticVideoApp
//
//  Codable trial log in UserDefaults + aggregate stats for blind A/B
//  haptics preference tests. Feeds the YC-application numbers.
//

import Foundation

// MARK: - Trial

struct ABTrial: Identifiable, Codable {
    enum Choice: String, Codable {
        case hapticsOn
        case hapticsOff
        case noDifference
    }

    var id: UUID = UUID()
    let date: Date
    let videoID: String
    let videoTitle: String
    let hapticsWasFirst: Bool
    let choice: Choice
}

// MARK: - Store

@MainActor
final class ABTestStore: ObservableObject {
    static let shared = ABTestStore()

    @Published private(set) var trials: [ABTrial] = []

    // ponytail: UserDefaults JSON blob — trials are tiny; move to a file if this ever holds thousands.
    private let defaultsKey = "abTestTrials.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([ABTrial].self, from: data) {
            trials = saved
        }
    }

    func record(videoID: String, videoTitle: String, hapticsWasFirst: Bool, choice: ABTrial.Choice) {
        trials.append(ABTrial(date: Date(),
                              videoID: videoID,
                              videoTitle: videoTitle,
                              hapticsWasFirst: hapticsWasFirst,
                              choice: choice))
        save()
    }

    func reset() {
        trials = []
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(trials) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    // MARK: - Aggregates

    var totalTrials: Int { trials.count }
    var noDifferenceCount: Int { trials.filter { $0.choice == .noDifference }.count }
    /// Trials where the tester felt a difference (picked A or B).
    var decidedTrials: Int { totalTrials - noDifferenceCount }
    var preferredHaptics: Int { trials.filter { $0.choice == .hapticsOn }.count }

    /// % preferring haptics among testers who felt a difference. Nil until someone decides.
    var percentPreferHaptics: Double? {
        guard decidedTrials > 0 else { return nil }
        return Double(preferredHaptics) / Double(decidedTrials) * 100
    }

    // MARK: - Per-video breakdown

    struct VideoStats: Identifiable {
        let id: String        // videoID
        let title: String
        let hapticsOn: Int
        let hapticsOff: Int
        let noDifference: Int
        var total: Int { hapticsOn + hapticsOff + noDifference }
        var decided: Int { hapticsOn + hapticsOff }
        var preferenceFraction: Double {
            decided > 0 ? Double(hapticsOn) / Double(decided) : 0
        }
    }

    var perVideoStats: [VideoStats] {
        Dictionary(grouping: trials, by: \.videoID)
            .map { id, ts in
                VideoStats(id: id,
                           title: ts.first?.videoTitle ?? id,
                           hapticsOn: ts.filter { $0.choice == .hapticsOn }.count,
                           hapticsOff: ts.filter { $0.choice == .hapticsOff }.count,
                           noDifference: ts.filter { $0.choice == .noDifference }.count)
            }
            .sorted { $0.total > $1.total }
    }

    // MARK: - Share text

    /// The YC-ready sentence plus per-video breakdown.
    var shareSummary: String {
        var lines = ["\(preferredHaptics)/\(decidedTrials) testers preferred the haptic version in blind A/B."]
        if let pct = percentPreferHaptics {
            lines.append(String(format: "%.0f%% preference among testers who felt a difference (%d total trials, %d reported no difference).",
                                pct, totalTrials, noDifferenceCount))
        }
        for v in perVideoStats {
            lines.append("- \(v.title): \(v.hapticsOn)/\(v.decided) preferred haptics (\(v.total) trials)")
        }
        return lines.joined(separator: "\n")
    }
}
