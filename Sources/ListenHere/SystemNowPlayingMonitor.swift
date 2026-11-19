import Foundation
import MediaPlayer

/// Monitors the macOS Now Playing system for track information.
/// This reads from the system's MPNowPlayingInfoCenter which is used by Control Center.
/// 
/// Works with any app that publishes Now Playing info (Yandex Music, Spotify, Apple Music, etc.)
/// This is the most reliable method because it uses the official Apple framework.
struct SystemNowPlaying: Equatable {
    let title: String
    let artist: String
    let album: String?
    let duration: Double
    let position: Double
    let isPlaying: Bool
    
    var identity: String { "\(artist.lowercased())\u{001F}\(title.lowercased())" }
}

enum SystemNowPlayingResult {
    case track(SystemNowPlaying)
    case appNotRunning
    case noData
    case permissionDenied
}

private func readNowPlayingInfo() -> SystemNowPlayingResult {
    let center = MPNowPlayingInfoCenter.default()
    guard let info = center.nowPlayingInfo else {
        return .noData
    }
    
    // Use string-based dictionary keys for macOS compatibility
    let titleKey = "MPNowPlayingInfoPropertyTitle" as NSString
    let artistKey = "MPNowPlayingInfoPropertyArtist" as NSString
    let albumKey = "MPNowPlayingInfoPropertyAlbumTitle" as NSString
    let durationKey = "MPNowPlayingInfoPropertyDuration" as NSString
    let positionKey = "MPNowPlayingInfoPropertyElapsedPlaybackTime" as NSString
    let rateKey = "MPNowPlayingInfoPropertyPlaybackRate" as NSString
    
    guard let title = info[titleKey as String] as? String,
          !title.isEmpty else {
        return .noData
    }
    
    let artist = info[artistKey as String] as? String ?? ""
    let album = info[albumKey as String] as? String
    let duration = (info[durationKey as String] as? NSNumber)?.doubleValue ?? 0
    let position = (info[positionKey as String] as? NSNumber)?.doubleValue ?? 0
    let playbackRate = (info[rateKey as String] as? NSNumber)?.doubleValue ?? 0
    let isPlaying = playbackRate > 0
    
    guard duration > 0 else {
        return .noData
    }
    
    let track = SystemNowPlaying(
        title: title,
        artist: artist,
        album: album,
        duration: duration,
        position: position,
        isPlaying: isPlaying
    )
    
    return .track(track)
}

/// Callback type for monitor results (non-Sendable for Thread safety)
typealias SystemNowPlayingCallback = @Sendable (SystemNowPlayingResult) -> Void

/// Monitor for system Now Playing info
final class SystemNowPlayingMonitor {
    private var callback: SystemNowPlayingCallback?
    private var timer: Timer?
    private let lock = NSLock()
    
    func setCallback(_ callback: @escaping SystemNowPlayingCallback) {
        lock.lock()
        self.callback = callback
        lock.unlock()
    }
    
    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [callback] _ in
            let result = readNowPlayingInfo()
            Task { @MainActor [callback] in
                callback?(result)
            }
        }
        poll()
    }
    
    func stop() {
        lock.lock()
        timer?.invalidate()
        timer = nil
        let cb = self.callback
        lock.unlock()
        Task { @MainActor [cb] in
            cb?(.appNotRunning)
        }
    }
    
    private func poll() {
        let result = readNowPlayingInfo()
        Task { @MainActor [callback = self.callback] in
            callback?(result)
        }
    }
}