import SwiftUI
import Combine
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var statusText = "Подключите Last.fm и включите скробблинг"
    @Published var currentTrack: Track?
    @Published var currentAlbum: String?
    @Published var playbackPosition: Double = 0
    @Published var playbackDuration: Int = 0
    @Published var isPlaying = false
    @Published var isScrobblingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isScrobblingEnabled, forKey: "listenhere_scrobbling_enabled")
            updateMonitoring()
        }
    }
    @Published var needsAccessibilityPermission = false
    @Published var useLoggingMonitor = false // New: use logging-based monitoring as fallback
    @Published var recentScrobbles: [String] = []
    @Published var submittedCount = 0

    let lastFM = LastFmService.shared

    private let yandexMonitor = YandexMusicMonitorService()
    private let loggingMonitor = YandexLoggingMonitorService() // New: fallback logging monitor
    private let legacyMonitor = PlayerMonitorService()
    private var activeIdentity: String?
    private var currentStartedAt: Int = 0
    private var listenedSeconds = 0.0
    private var previousSampleAt: Date?
    private var didScrobbleCurrentTrack = false
    private var pending: [PendingScrobble] = []
    private var isFlushingPending = false
    private var nextRetryDate = Date.distantPast

    private struct PendingScrobble: Codable {
        let title: String
        let artist: String
        let album: String?
        let duration: Int
        let timestamp: Int

        var item: LastFMScrobble {
            LastFMScrobble(track: Track(title: title, artist: artist), album: album,
                           duration: duration, timestamp: timestamp)
        }
    }

    init() {
        isScrobblingEnabled = UserDefaults.standard.object(forKey: "listenhere_scrobbling_enabled") as? Bool ?? false
        useLoggingMonitor = UserDefaults.standard.bool(forKey: "listenhere_use_logging_monitor")
        pending = (try? JSONDecoder().decode([PendingScrobble].self,
                    from: UserDefaults.standard.data(forKey: "listenhere_pending_scrobbles") ?? Data())) ?? []
        recentScrobbles = UserDefaults.standard.stringArray(forKey: "listenhere_recent_scrobbles") ?? []
        submittedCount = UserDefaults.standard.integer(forKey: "listenhere_submitted_count")

        yandexMonitor.onUpdate = { [weak self] result in
            guard let self else { return }
            // If AX fails and logging fallback is enabled, try logging monitor
            if case .cannotRead = result, self.useLoggingMonitor {
                self.loggingMonitor.onUpdate?(self.loggingMonitorResultToYandex(result))
            } else {
                self.handleYandexResult(result)
            }
        }
        
        // New: handle logging monitor results
        loggingMonitor.onUpdate = { [weak self] result in
            guard let self else { return }
            self.handleLoggingResult(result)
        }
        
        legacyMonitor.onTrackChange = { [weak self] track in
            guard let self, self.currentTrack == nil || self.activeIdentity == nil else { return }
            self.currentTrack = track
            self.statusText = "Найдено через плеер · Яндекс отслеживается отдельно"
        }
        updateMonitoring()
    }
    
    /// Convert logging monitor result to Yandex monitor result
    private func loggingMonitorResultToYandex(_ result: YandexLogMonitorResult) -> YandexMonitorResult? {
        switch result {
        case .track(let playback):
            return .track(YandexPlayback(
                title: playback.title,
                artist: playback.artist,
                album: playback.album,
                duration: playback.duration,
                position: playback.position,
                isPlaying: playback.isPlaying
            ))
        case .appNotRunning:
            // Return nil to indicate no track
            return nil
        default:
            return nil
        }
    }
    
    /// Handle Yandex monitor results
    private func handleYandexResult(_ result: YandexMonitorResult) {
        switch result {
        case .track(let playback):
            self.receive(playback)
        case .appNotRunning:
            self.receive(nil)
            self.statusText = "Яндекс Музыка не запущена"
        case .cannotRead(let code):
            self.needsAccessibilityPermission = true
            self.isPlaying = false
            self.statusText = "macOS отклонила чтение окна Яндекс Музыки (AX \(code)). Перезапустите Listen Here или проверьте разрешение."
            // Try logging monitor as fallback
            if useLoggingMonitor {
                self.loggingMonitor.start()
                self.statusText = "Пытаюсь прочитать через логгирование..."
            }
        case .noWindow:
            self.isPlaying = false
            self.statusText = "Не удалось получить окно Яндекс Музыки"
        case .noTrackMetadata:
            self.isPlaying = false
            self.statusText = "Доступ к окну есть, но данные текущего трека не найдены"
        }
    }
    
    /// Handle logging monitor results
    private func handleLoggingResult(_ result: YandexLogMonitorResult) {
        switch result {
        case .track(let playback):
            self.receive(YandexPlayback(
                title: playback.title,
                artist: playback.artist,
                album: playback.album,
                duration: playback.duration,
                position: playback.position,
                isPlaying: playback.isPlaying
            ))
            self.statusText = "Яндекс Музыка (через логи) · данные получены"
        case .appNotRunning:
            self.receive(nil)
            self.isPlaying = false
            self.statusText = "Яндекс Музыка не запущена"
        case .noData:
            // No data via logging, keep current state
            break
        case .permissionDenied:
            self.isPlaying = false
            self.statusText = "Доступ к логам запрещён"
        }
    }

    var accessibilitySettingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")
    }

    var pendingCount: Int { pending.count }

    func lastFMConnectionChanged() {
        updateMonitoring()
    }

    func requestAccessibilityPermission() {
        if !YandexMusicMonitorService.requestAccessibilityPermission() {
            needsAccessibilityPermission = true
        } else {
            needsAccessibilityPermission = false
            updateMonitoring()
        }
    }

    func openAccessibilitySettings() {
        if let accessibilitySettingsURL { NSWorkspace.shared.open(accessibilitySettingsURL) }
    }

    private func updateMonitoring() {
        guard isScrobblingEnabled else {
            yandexMonitor.stop()
            loggingMonitor.stop()
            legacyMonitor.stop()
            isPlaying = false
            statusText = "Скробблинг выключен"
            return
        }
        guard lastFM.isLoggedIn else {
            yandexMonitor.stop()
            loggingMonitor.stop()
            legacyMonitor.stop()
            statusText = "Подключите Last.fm, чтобы начать скробблинг"
            return
        }
        if !YandexMusicMonitorService.hasAccessibilityPermission {
            needsAccessibilityPermission = true
            _ = YandexMusicMonitorService.requestAccessibilityPermission()
            statusText = "Проверяю доступ к окну Яндекс Музыки…"
        } else {
            needsAccessibilityPermission = false
        }
        
        // Start appropriate monitors based on settings
        if useLoggingMonitor {
            // Try logging monitor as primary fallback
            loggingMonitor.start()
            statusText = "Пытаюсь прочитать данные через логгирование Яндекс Музыки…"
        } else {
            // Use Accessibility API as primary method
            legacyMonitor.start()
            yandexMonitor.start()
            if YandexMusicMonitorService.hasAccessibilityPermission {
                statusText = "Ищу Яндекс Музыку…"
            }
        }
        retryPendingScrobbles()
    }

    private func receive(_ playback: YandexPlayback?) {
        guard isScrobblingEnabled else { return }
        retryPendingScrobbles()
        guard let playback else {
            isPlaying = false
            previousSampleAt = nil
            statusText = needsAccessibilityPermission
                ? "Проверяю доступ к окну Яндекс Музыки…"
                : "Жду воспроизведение в Яндекс Музыке"
            return
        }

        needsAccessibilityPermission = false
        let now = Date()
        currentTrack = Track(title: playback.title, artist: playback.artist)
        currentAlbum = playback.album
        playbackPosition = playback.position
        playbackDuration = playback.duration
        isPlaying = playback.isPlaying

        if activeIdentity != playback.identity {
            activeIdentity = playback.identity
            currentStartedAt = Int(now.timeIntervalSince1970 - playback.position)
            listenedSeconds = 0
            previousSampleAt = playback.isPlaying ? now : nil
            didScrobbleCurrentTrack = false
            statusText = playback.isPlaying ? "Яндекс Музыка · отправляю Now Playing" : "На паузе в Яндекс Музыке"
            sendNowPlaying(playback)
        } else if playback.isPlaying {
            if let previousSampleAt {
                let delta = now.timeIntervalSince(previousSampleAt)
                // Ignore long gaps, app sleep, and time spent with the monitor paused.
                if delta > 0 && delta <= 7 { listenedSeconds += delta }
            }
            previousSampleAt = now
        } else {
            previousSampleAt = nil
            statusText = "На паузе в Яндекс Музыке"
        }

        guard !didScrobbleCurrentTrack, playback.duration > 30 else { return }
        let required = min(Double(playback.duration) / 2, 240)
        guard listenedSeconds >= required else {
            if playback.isPlaying {
                statusText = "Слушаете · до скроббла \(max(0, Int(ceil(required - listenedSeconds)))) сек."
            }
            return
        }
        didScrobbleCurrentTrack = true
        enqueue(playback)
    }

    private func sendNowPlaying(_ playback: YandexPlayback) {
        guard lastFM.isLoggedIn else { return }
        let item = LastFMScrobble(track: Track(title: playback.title, artist: playback.artist),
                                  album: playback.album, duration: playback.duration,
                                  timestamp: currentStartedAt)
        Task {
            do { try await lastFM.sendNowPlaying(item); statusText = "Сейчас играет · Last.fm обновлён" }
            catch { statusText = "Now Playing: \(error.localizedDescription)" }
        }
    }

    private func enqueue(_ playback: YandexPlayback) {
        let record = PendingScrobble(title: playback.title, artist: playback.artist, album: playback.album,
                                     duration: playback.duration, timestamp: currentStartedAt)
        pending.append(record)
        persistPending()
        retryPendingScrobbles()
    }

    private func retryPendingScrobbles() {
        guard lastFM.isLoggedIn, !pending.isEmpty, !isFlushingPending, Date() >= nextRetryDate else { return }
        isFlushingPending = true
        Task {
            defer { isFlushingPending = false }
            while !pending.isEmpty, lastFM.isLoggedIn {
                let record = pending[0]
                do {
                    try await lastFM.scrobble(record.item)
                    pending.removeFirst()
                    submittedCount += 1
                    UserDefaults.standard.set(submittedCount, forKey: "listenhere_submitted_count")
                    let label = "\(record.artist) — \(record.title)"
                    recentScrobbles.insert(label, at: 0)
                    recentScrobbles = Array(recentScrobbles.prefix(8))
                    UserDefaults.standard.set(recentScrobbles, forKey: "listenhere_recent_scrobbles")
                    statusText = "Скроббл отправлен · \(record.artist) — \(record.title)"
                    persistPending()
                } catch {
                    nextRetryDate = Date().addingTimeInterval(60)
                    statusText = "Ожидает отправки · \(error.localizedDescription)"
                    persistPending()
                    break
                }
            }
        }
    }

    private func persistPending() {
        if let data = try? JSONEncoder().encode(pending) {
            UserDefaults.standard.set(data, forKey: "listenhere_pending_scrobbles")
        }
    }
}
