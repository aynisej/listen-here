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
    
    var identity: String { "\(artist.lowercased())\u{1f}\(title.lowercased())" }
}

enum SystemNowPlayingResult {
    case track(SystemNowPlaying)
    case appNotRunning
    case noData
    case permissionDenied
}

final class SystemNowPlayingMonitor: ObservableObject {
    var onUpdate: ((SystemNowPlayingResult) -> Void)?
    private var timer: Timer?
    private var isPolling = false
    
    private let center = MPNowPlayingInfoCenter.defaultCenter()
    
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
        onUpdate?(.appNotRunning)
    }
    
    private func poll() {
        guard !isPolling else { return }
        isPolling = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let result = self.readNowPlaying()
            DispatchQueue.main.async {
                self.isPolling = false
                self.onUpdate?(result)
            }
        }
    }
    
    private func readNowPlaying() -> SystemNowPlayingResult {
        guard let info = center.nowPlayingInfo else {
            return .noData
        }
        
        guard let title = info[MPNowPlayingInfoPropertyTitle] as? String,
              !title.isEmpty else {
            return .noData
        }
        
        let artist = info[MPNowPlayingInfoPropertyArtist] as? String ?? ""
        let album = info[MPNowPlayingInfoPropertyAlbumTitle] as? String
        let duration = (info[MPNowPlayingInfoPropertyDuration] as? NSNumber)?.doubleValue ?? 0
        let position = (info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? NSNumber)?.doubleValue ?? 0
        let playbackRate = (info[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue ?? 0
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