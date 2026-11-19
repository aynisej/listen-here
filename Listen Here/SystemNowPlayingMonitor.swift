import Foundation
import MediaPlayer
import Combine

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

@MainActor
final class SystemNowPlayingMonitor: ObservableObject {
    var onUpdate: ((SystemNowPlayingResult) -> Void)?
    private var timer: Timer?
    private var isPolling = false
    
    private let center = MPNowPlayingInfoCenter.default()
    
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.poll()
            }
        }
        Task { @MainActor in
            await self?.poll()
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
        onUpdate?(.appNotRunning)
    }
    
    private func poll() async {
        guard !isPolling else { return }
        isPolling = true
        let result = readNowPlaying()
        isPolling = false
        onUpdate?(result)
    }
    
    private func readNowPlaying() -> SystemNowPlayingResult {
        guard let info = center.nowPlayingInfo else {
            return .noData
        }
        
        // Use string-based dictionary keys for macOS compatibility
        // MPNowPlayingInfoProperty* constants are iOS-specific
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
}