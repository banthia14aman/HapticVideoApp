//
//  LocalDataStore.swift
//  HapticVideoApp
//
//  On-device store: media files in Documents, metadata index in videos.json.
//  The index stores bare FILENAMES, not absolute URLs — the app container
//  path changes across reinstalls/rebuilds, so absolute paths go stale.
//  Filenames are resolved against the current Documents directory on read.
//

import Foundation
import UIKit

/// NSCache-backed thumbnail loader so views don't hit disk every render.
/// INTEGRATION: views should replace `UIImage(contentsOfFile:)` /
/// AsyncImage-on-file-URL with `ThumbnailCache.image(forPath:)`.
enum ThumbnailCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(forPath path: String) -> UIImage? {
        if let hit = cache.object(forKey: path as NSString) { return hit }
        guard let img = UIImage(contentsOfFile: path) else { return nil }
        cache.setObject(img, forKey: path as NSString)
        return img
    }
}

final class LocalDataStore: VideoDataStore {
    static let shared = LocalDataStore()
    private init() {}

    private let userKey = "currentUser"
    /// One orphan sweep per launch, from the first fetchAllVideos.
    private var sweptThisLaunch = false

    private var docs: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var indexURL: URL { docs.appendingPathComponent("videos.json") }
    private var indexBackupURL: URL { docs.appendingPathComponent("videos.json.bak") }

    // MARK: - Index

    /// Reads videos.json; on a corrupt/undecodable index falls back to the
    /// last-good backup, then to empty. One bad write never loses the library.
    private func readIndex() throws -> [Video] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for url in [indexURL, indexBackupURL] {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let videos = try? decoder.decode([Video].self, from: data) { return videos }
        }
        return []
    }

    private func writeIndex(_ videos: [Video]) throws {
        let fm = FileManager.default
        // Keep the previous good index as a backup before overwriting.
        if fm.fileExists(atPath: indexURL.path) {
            try? fm.removeItem(at: indexBackupURL)
            try? fm.copyItem(at: indexURL, to: indexBackupURL)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // .atomic = write-to-temp + rename; a crash mid-write can't corrupt.
        try encoder.encode(videos).write(to: indexURL, options: .atomic)
    }

    /// All index-referenced local filenames (skips cloud URLs).
    private func referencedNames(in index: [Video]) -> Set<String> {
        Set(index.flatMap { [$0.videoURL, $0.thumbnailURL, $0.hapticsURL].compactMap { $0 } }
            .filter { !$0.contains("://") })
    }

    // MARK: - Storage Maintenance

    /// INTEGRATION: Profile can show this via AppBackend.store.storageUsage().
    func storageUsage() -> (videoCount: Int, bytes: Int64) {
        let index = (try? readIndex()) ?? []
        let bytes = referencedNames(in: index).reduce(Int64(0)) { total, name in
            let attrs = try? FileManager.default.attributesOfItem(
                atPath: docs.appendingPathComponent(name).path)
            return total + ((attrs?[.size] as? Int64) ?? 0)
        }
        return (index.count, bytes)
    }

    /// Deletes media files we own (*.mp4 / *.jpg / *.haptics.json, excluding
    /// draft-*) that no index row references.
    func sweepOrphans() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: docs.path) else { return }
        let referenced = referencedNames(in: (try? readIndex()) ?? [])
        for name in files where !name.hasPrefix("draft-") && !referenced.contains(name)
            && (name.hasSuffix(".mp4") || name.hasSuffix(".jpg") || name.hasSuffix(".haptics.json")) {
            try? fm.removeItem(at: docs.appendingPathComponent(name))
        }
    }

    /// Prototype storage shouldn't bloat iCloud backups.
    private func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// Index rows hold filenames; views need absolute file URLs.
    private func resolved(_ video: Video) -> Video {
        func abs(_ name: String) -> String {
            name.contains("://") ? name : docs.appendingPathComponent(name).absoluteString
        }
        var v = video
        v.videoURL = abs(v.videoURL)
        v.thumbnailURL = abs(v.thumbnailURL)
        if let h = v.hapticsURL { v.hapticsURL = abs(h) }
        return v
    }

    // MARK: - Demo Content

    /// Copies bundled demo clips (authored haptic tracks included) into
    /// Documents and indexes them on first launch — built-in A/B material.
    private func seedDemoContentIfNeeded() {
        let seededKey = "demoContentSeeded.v1"
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }

        func bundled(_ name: String, _ ext: String) -> URL? {
            Bundle.main.url(forResource: name, withExtension: ext)
                ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Demos")
                ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/Demos")
        }

        let demos: [(base: String, title: String, desc: String, duration: Double)] = [
            ("demo-bass-drop",   "Bass Drop",      "Feel the silence before the drop", 12.0),
            ("demo-clicks",      "Clicks & Ticks", "Crisp transients, zero rumble",    10.0),
            ("demo-transitions", "Transitions",    "Risers and impacts you can feel",  13.5),
        ]

        var index = (try? readIndex()) ?? []
        var seededAny = false
        for (demoIndex, demo) in demos.enumerated() {
            guard let videoSrc = bundled(demo.base, "mp4"),
                  let thumbSrc = bundled(demo.base, "jpg"),
                  let hapticsSrc = bundled("\(demo.base).haptics", "json") else {
                print("⚠️ Demo assets missing for \(demo.base)")
                continue
            }
            let names = (video: "\(demo.base).mp4", thumb: "\(demo.base).jpg",
                         haptics: "\(demo.base).haptics.json")
            do {
                for (src, name) in [(videoSrc, names.video), (thumbSrc, names.thumb), (hapticsSrc, names.haptics)] {
                    let dst = docs.appendingPathComponent(name)
                    if !FileManager.default.fileExists(atPath: dst.path) {
                        try FileManager.default.copyItem(at: src, to: dst)
                        if name.hasSuffix(".mp4") { excludeFromBackup(dst) }
                    }
                }
                index.removeAll { $0.id == demo.base }
                index.append(Video(
                    id: demo.base, title: demo.title,
                    videoURL: names.video, thumbnailURL: names.thumb,
                    uploaderID: "demo", uploaderUsername: "HapticVideo",
                    // Past-dated: a now() timestamp renders as "in 0 sec"
                    // (clock skew) and staggering gives a natural feed order.
                    uploadedAt: Date().addingTimeInterval(-Double(demoIndex + 1) * 86_400), duration: demo.duration,
                    hasHaptics: true, hapticsURL: names.haptics,
                    views: 0, description: demo.desc))
                seededAny = true
            } catch {
                print("⚠️ Demo seed failed for \(demo.base): \(error)")
            }
        }
        if seededAny {
            try? writeIndex(index)
            UserDefaults.standard.set(true, forKey: seededKey)
            print("🎁 Seeded \(demos.count) demo videos")
        }
    }

    // MARK: - VideoDataStore

    func fetchAllVideos() async throws -> [Video] {
        seedDemoContentIfNeeded()
        if !sweptThisLaunch {
            sweptThisLaunch = true
            sweepOrphans()
        }
        return try readIndex()
            .sorted { $0.uploadedAt > $1.uploadedAt }
            .map(resolved)
    }

    func fetchVideo(byId id: String) async throws -> Video? {
        try readIndex().first { $0.id == id }.map(resolved)
    }

    @discardableResult
    func uploadVideo(video: Video, videoData: Data, videoFileExtension: String, thumbnailData: Data, hapticsData: Data?) async throws -> Video {
        var row = video
        // Preserve the source container extension — renaming (e.g. mov->mp4)
        // breaks AVURLAsset type inference at playback time.
        let ext = videoFileExtension.isEmpty ? "mp4" : videoFileExtension
        let videoName = "\(video.id).\(ext)"
        let thumbName = "\(video.id).jpg"
        let videoDst = docs.appendingPathComponent(videoName)
        try videoData.write(to: videoDst, options: .atomic)
        excludeFromBackup(videoDst)
        try thumbnailData.write(to: docs.appendingPathComponent(thumbName), options: .atomic)
        row.videoURL = videoName
        row.thumbnailURL = thumbName
        if let hapticsData {
            let hapticsName = "\(video.id).haptics.json"
            try hapticsData.write(to: docs.appendingPathComponent(hapticsName), options: .atomic)
            row.hapticsURL = hapticsName
        }

        var index = try readIndex()
        index.removeAll { $0.id == row.id }
        index.append(row)
        try writeIndex(index)

        // Cosmetic: bump the local profile's upload count
        if var user = loadUser(), user.id == row.uploaderID {
            user.videosUploaded += 1
            saveUserMetadata(user)
        }

        return resolved(row)
    }

    func incrementViews(videoId: String) async throws {
        var index = try readIndex()
        guard let i = index.firstIndex(where: { $0.id == videoId }) else { return }
        index[i].views += 1
        try writeIndex(index)
    }

    func deleteVideo(_ video: Video) async throws {
        var index = try readIndex()
        if let row = index.first(where: { $0.id == video.id }) {
            for name in [row.videoURL, row.thumbnailURL, row.hapticsURL].compactMap({ $0 }) {
                try? FileManager.default.removeItem(at: docs.appendingPathComponent(name))
            }
        }
        index.removeAll { $0.id == video.id }
        try writeIndex(index)
    }

    // MARK: - Local User

    func saveUserMetadata(_ user: User) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(user) {
            UserDefaults.standard.set(data, forKey: userKey)
        }
    }

    func loadUser() -> User? {
        guard let data = UserDefaults.standard.data(forKey: userKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(User.self, from: data)
    }

    func clearUser() {
        UserDefaults.standard.removeObject(forKey: userKey)
    }
}
