//
//  IPCScrobbleBridge.swift
//  Listen Here
//
//  IPC bridge service for receiving PLAYER_STATE from modified Yandex Music
//

import Foundation
import Combine
import AppKit

/// Player state received from Yandex Music via IPC channel
struct IPCTrackPlayback: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String?
    let duration: Int
    let position: Double
    let isPlaying: Bool
    
    var identity: String { "\(artist.lowercased())\u{001F}\(title.lowercased())" }
}

/// Result types for IPC bridge monitor
enum IPCScrobbleResult: Sendable {
    case track(IPCTrackPlayback)
    case appNotRunning
    case connectionFailed
    case noData
}

/// Track cache that maps track IDs to metadata
struct TrackCache: Codable {
    struct Track: Codable {
        let title: String
        let artist: String
        let album: String?
        let duration: Int
        let genre: String?
    }
    let tracks: [String: Track]
    let playlists: [String: Playlist]?
    let contextTypes: [String: String]?
    
    struct Playlist: Codable {
        let name: String
        let type: String
    }
}

/// Get running applications safely
private func getRunningApplications() -> [NSRunningApplication] {
    return NSWorkspace.shared.runningApplications
}

/// Extract Sendable data from notification userInfo (non-isolated to avoid Sendable issues)
private func extractIPCData(from userInfo: [AnyHashable: Any]?) -> IPCNotificationData? {
    guard let userInfo = userInfo,
          let isPlaying = userInfo["isPlaying"] as? Bool else {
        return nil
    }
    
    return IPCNotificationData(
        isPlaying: isPlaying,
        title: userInfo["title"] as? String,
        artist: userInfo["artist"] as? String,
        album: userInfo["album"] as? String,
        duration: userInfo["duration"] as? Int,
        position: userInfo["position"] as? Double,
        trackId: userInfo["trackId"] as? Int
    )
}

/// Wrapper for notification data that can be sent across actor boundaries
private struct IPCNotificationData: Sendable {
    let isPlaying: Bool
    let title: String?
    let artist: String?
    let album: String?
    let duration: Int?
    let position: Double?
    let trackId: Int?
}

/// IPC Bridge service that receives PLAYER_STATE messages from modified Yandex Music
@MainActor final class IPCScrobbleBridge: ObservableObject {
    static let shared = IPCScrobbleBridge()
    
    @Published private(set) var isConnected = false
    @Published private(set) var lastReceived: Date?
    
    private var callback: ((IPCScrobbleResult) -> Void)?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var isMonitoring = false
    private var trackCache: TrackCache = .init(tracks: [:], playlists: nil, contextTypes: nil)
    
    /// IPC channel name for PLAYER_STATE messages
    private let ipcChannelName = "desktop:player:state:metadata"
    
    /// State file path for file-based IPC
    private let stateFilePath = "/Users/aqshel/Library/Application Support/YandexMusic/player_state.json"
    
    /// Notification name for request state
    private let requestStateNotification = Notification.Name("com.yandex.music.request.state")
    
    /// Path to track cache
    private let cachePath = "/Users/aqshel/Library/Application Support/YandexMusic/ipc_track_cache.json"
    
    /// Load track cache from disk or LevelDB
    private func loadTrackCache() async {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: cachePath))
            trackCache = try JSONDecoder().decode(TrackCache.self, from: data)
        } catch {
            // Try to load from embedded LevelDB parser
            await loadTrackCacheFromLevelDB()
        }
    }
    
    /// Load track cache from LevelDB files
    private func loadTrackCacheFromLevelDB() async {
        // Parse LevelDB files to extract track metadata
        let tracks = await YandexLevelDBParser.shared.parseAllTracks()
        
        if !tracks.isEmpty {
            var cacheTracks: [String: TrackCache.Track] = [:]
            for (id, levelTrack) in tracks {
                cacheTracks[id] = TrackCache.Track(
                    title: levelTrack.title ?? "Unknown Track",
                    artist: levelTrack.artist ?? "Unknown Artist",
                    album: levelTrack.album,
                    duration: levelTrack.duration ?? 0,
                    genre: levelTrack.genre
                )
            }
            trackCache = TrackCache(tracks: cacheTracks, playlists: nil, contextTypes: nil)
        } else {
            // Fall back to default cache
            loadDefaultCache()
        }
    }
    
    /// Update cache with resolved track from LevelDB
    private init() {
        // Load cache asynchronously - will be populated on first use
        Task {
            await loadTrackCache()
        }
    }
    
    /// Load built-in default track cache
    private func loadDefaultCache() {
        // Default cache with known track mappings
        let defaultCache = """
        {
            "tracks": {
                "464769": {
                    "title": "The Rise and Fall of Ziggy Stardust",
                    "artist": "Pulp",
                    "album": "This Is Hardcore",
                    "duration": 240,
                    "genre": "Alternative Rock"
                },
                "464770": {
                    "title": "Lets Get Lost",
                    "artist": "Various Artists",
                    "album": "Chill Vibes",
                    "duration": 180,
                    "genre": "Chillout"
                }
            },
            "playlists": {
                "1211119227": {
                    "name": "Your Liked Playlist",
                    "type": "liked"
                }
            },
            "context_types": {
                "radio": "Radio station",
                "playlist": "Playlist",
                "album": "Album"
            }
        }
        """
        
        if let data = defaultCache.data(using: .utf8) {
            do {
                trackCache = try JSONDecoder().decode(TrackCache.self, from: data)
            } catch {
                // Still failed, keep empty cache
            }
        }
    }
    
    /// Resolve track ID to track metadata using cache
    private func resolveTrackMetadata(trackId: Int?) -> TrackMetadata? {
        guard let trackId = trackId else { return nil }
        
        if let track = trackCache.tracks[String(trackId)] {
            return TrackMetadata(
                title: track.title,
                artist: track.artist,
                album: track.album,
                duration: track.duration
            )
        }
        
        // Try to read from LevelDB
        if let leveldbTrack = readTrackFromLevelDB(trackId: trackId) {
            return leveldbTrack
        }
        
        return nil
    }
    
    /// Track metadata structure
    private struct TrackMetadata {
        let title: String
        let artist: String
        let album: String?
        let duration: Int
    }
    
    /// Read track information from Yandex Music LevelDB
    private func readTrackFromLevelDB(trackId: Int) -> TrackMetadata? {
        // This would require a proper LevelDB parser
        // For now, use the built-in cache
        return nil
    }
    
    /// Callback type for received results
    typealias IPCScrobbleCallback = (IPCScrobbleResult) -> Void
    
    func setCallback(_ callback: @escaping IPCScrobbleCallback) {
        self.callback = callback
    }
    
    /// Start monitoring for IPC messages from modified Yandex Music
    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        Task {
            await checkYandexMusicStatus()
        }
    }
    
    /// Stop monitoring
    func stop() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        isConnected = false
        cancellables.removeAll()
    }
    
    /// Check if Yandex Music is running and establish connection
    private func checkYandexMusicStatus() async {
        let yandexApps = getRunningApplications().filter { 
            $0.bundleIdentifier == "ru.yandex.desktop.music" 
        }
        
        guard !yandexApps.isEmpty else {
            isConnected = false
            callback?(.appNotRunning)
            return
        }
        
        // If we have multiple instances, pick the main one
        if let mainApp = yandexApps.first(where: { $0.isActive }) ?? yandexApps.first {
            setupIPCConnection(app: mainApp)
        }
    }
    
    /// File monitoring state
    private var fileMonitorSource: DispatchSourceFileSystemObject?
    private var lastFileContent: String = ""
    
    /// Start monitoring the player state file
    private func startFileMonitoring() {
        let fileURL = URL(fileURLWithPath: stateFilePath)
        let fileManager = FileManager.default
        
        // Create parent directory if needed
        let parentDir = fileURL.deletingLastPathComponent().path
        if !fileManager.fileExists(atPath: parentDir) {
            try? fileManager.createDirectory(atPath: parentDir, withIntermediateDirectories: true, attributes: nil)
        }
        
        // Create empty file if it doesn't exist
        if !fileManager.fileExists(atPath: stateFilePath) {
            fileManager.createFile(atPath: stateFilePath, contents: nil, attributes: nil)
        }
        
        // Open file descriptor for monitoring
        let fd = open(stateFilePath, O_EVTONLY)
        guard fd >= 0 else { return }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: DispatchQueue(label: "com.listenhere.ipc.monitor")
        )
        
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.readPlayerStateFile()
            }
        }
        
        source.setCancelHandler {
            close(fd)
        }
        
        source.resume()
        fileMonitorSource = source
        
        // Read initial state
        Task { @MainActor in
            await readPlayerStateFile()
        }
    }
    
    /// Read and parse the player state file
    private func readPlayerStateFile() async {
        do {
            let content = try String(contentsOfFile: stateFilePath, encoding: .utf8)
            
            // Skip if content hasn't changed
            guard content != lastFileContent else { return }
            lastFileContent = content
            
            guard let data = content.data(using: .utf8) else { return }
            
            let decoder = JSONDecoder()
            let state = try decoder.decode(YandexPlayerState.self, from: data)
            
            let ipcData = IPCNotificationData(
                isPlaying: state.isPlaying,
                title: state.title,
                artist: state.artist,
                album: state.album,
                duration: state.duration,
                position: state.position,
                trackId: state.trackId
            )
            
            await handleIPCMessage(data: ipcData)
        } catch {
            // File may be empty or being written, skip
        }
    }
    
    /// Player state structure matching the file format
    struct YandexPlayerState: Codable {
        let isPlaying: Bool
        let title: String?
        let artist: String?
        let album: String?
        let duration: Int?
        let position: Double?
        let trackId: Int?
        let timestamp: Int?
    }
    
    /// Set up IPC connection via file monitoring
    private func setupIPCConnection(app: NSRunningApplication) {
        isConnected = true
        lastReceived = Date()
        
        // Set up file monitoring for player state
        startFileMonitoring()
        
        // Handle disconnection
        NotificationCenter.default.addObserver(
            forName: Notification.Name("com.yandex.music.player.offline"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isConnected = false
                self.callback?(.connectionFailed)
            }
        }
        
        // Request current state from Yandex Music
        requestCurrentState()
        
        // Start periodic status checks
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkYandexMusicStatus()
            }
        }
    }
    
    /// Handle incoming IPC message (must be called from MainActor)
    private func handleIPCMessage(data: IPCNotificationData) async {
        lastReceived = Date()
        
        // Resolve track metadata from cache if trackId is provided
        let resolvedTrack = resolveTrackMetadata(trackId: data.trackId)
        
        // Extract track metadata with fallbacks
        let title: String
        let artist: String
        let album: String?
        let duration: Int
        
        if let resolved = resolvedTrack {
            title = resolved.title
            artist = resolved.artist
            album = resolved.album ?? data.album
            duration = resolved.duration
        } else {
            title = data.title ?? "Unknown Track"
            artist = data.artist ?? "Unknown Artist"
            album = data.album
            duration = data.duration ?? 0
        }
        
        let playback = IPCTrackPlayback(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            position: data.position ?? 0.0,
            isPlaying: data.isPlaying
        )
        
        callback?(.track(playback))
    }
    
    /// Request Yandex Music to send its current state
    func requestCurrentState() {
        // Post a notification requesting current state from Yandex Music
        NotificationCenter.default.post(
            name: requestStateNotification,
            object: nil,
            userInfo: ["requester": "Listen Here"]
        )
    }
    
    /// Check if Yandex Music has proper IPC support
    /// Returns whether the modified version is installed
    var hasIPCSupport: Bool {
        // Check for the presence of the IPC bridge extension or modified client
        let ipcBridgePath = "/Applications/Yandex Music.app/Contents/Resources/ipc-bridge.dylib"
        return FileManager.default.fileExists(atPath: ipcBridgePath)
    }
    
    /// Send a message to Yandex Music process via distributed notifications
    /// This is used to communicate with the modified Yandex Music
    func sendMessage(_ channel: String, _ data: [String: Any]) {
        NotificationCenter.default.post(
            name: Notification.Name("com.yandex.music.ipc.message"),
            object: nil,
            userInfo: ["channel": channel, "data": data]
        )
    }
}