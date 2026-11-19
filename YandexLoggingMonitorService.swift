import Foundation
import os.log

/// Alternative monitor service that reads track information from logging output.
/// This is useful when Accessibility API fails or Yandex Music updates its UI.
/// 
/// The service monitors system logs for entries published by the Yandex Music client.
/// These logs may contain track metadata in structured (JSON) or plain text format.
///
/// Usage:
///   1. Enable debug logging in Yandex Music (if available via Terminal flags)
///   2. Or use macOS Console app to redirect logs to a file
///   3. Configure this service to read from the specified log source
///
/// Note: This is a fallback/coping mechanism and may not work with all Yandex Music versions.

struct YandexLogPlayback: Equatable {
    let title: String
    let artist: String
    let album: String?
    let duration: Int
    let position: Double
    let isPlaying: Bool
    
    var identity: String { "\(artist.lowercased())\u{1f}\(title.lowercased())" }
}

enum YandexLogMonitorResult {
    case track(YandexLogPlayback)
    case appNotRunning
    case noData
    case permissionDenied
}

final class YandexLoggingMonitorService {
    var onUpdate: ((YandexLogMonitorResult) -> Void)?
    private var timer: Timer?
    private var isPolling = false
    
    /// Path to the log file or command output to monitor
    /// Examples:
    ///   - "/var/log/YandexMusic.log" (if Yandex writes to a file)
    ///   - "$(getconf DARWIN_USER_CACHE_DIR)/YandexMusic/logs/" (user cache logs)
    ///   - Empty string to use system log monitoring
    private let logSource: String
    
    /// Initialize with optional custom log source path
    init(logSource: String = "") {
        self.logSource = logSource
    }
    
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
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
            let result = self?.readFromLog() ?? .noData
            DispatchQueue.main.async {
                self?.isPolling = false
                self?.onUpdate?(result)
            }
        }
    }
    
    /// Read track information from log source
    private func readFromLog() -> YandexLogMonitorResult {
        var playback: YandexLogPlayback?
        
        if logSource.isEmpty {
            // Try to use system logging APIs
            playback = readFromSystemLog()
        } else {
            // Read from file-based logging
            playback = readFromLogFile()
        }
        
        if let playback = playback {
            return .track(playback)
        }
        
        // Check if Yandex Music is running
        if isYandexMusicRunning() {
            return .noData
        } else {
            return .appNotRunning
        }
    }
    
    /// Check if Yandex Music is running
    private func isYandexMusicRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-ax"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            return output.contains("Yandex") && output.contains("Music")
        } catch {
            return false
        }
    }
    
    /// Method 1: Read from system log using os_log and log command
    /// This requires Yandex Music to use os_log for track events
    private func readFromSystemLog() -> YandexLogPlayback? {
        // Try to read recent logs from Yandex Music process
        // Note: This is experimental and may not work depending on Yandex Music's logging
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        task.arguments = [
            "show", "--predicate", "subsystem == \"ru.yandex.desktop.music\" OR process == \"Yandex Music\"",
            "--last", "1m",
            "--style", "json"
        ]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8), !output.isEmpty else {
                return nil
            }
            
            return parseLogOutput(output)
        } catch {
            return nil
        }
    }
    
    /// Method 2: Read from a file-based log
    /// This requires Yandex Music to write to a log file
    private func readFromLogFile() -> YandexLogPlayback? {
        // Check if log file exists
        let logURL = URL(fileURLWithPath: logSource)
        guard FileManager.default.fileExists(atPath: logSource) else {
            // Try the default Yandex Music log location
            let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            let defaultLogPath = cacheDir?.appendingPathComponent("YandexMusic/logs/current.log").path
            
            if let defaultPath = defaultLogPath, FileManager.default.fileExists(atPath: defaultPath) {
                return parseLogFile(at: defaultPath)
            }
            return nil
        }
        
        return parseLogFile(at: logSource)
    }
    
    /// Parse JSON or text log entries
    private func parseLogOutput(_ output: String) -> YandexLogPlayback? {
        // Try to parse as JSON first (structured logging)
        let lines = output.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        for line in lines.reversed() {
            // Try JSON format
            if let playback = tryParseJSONLog(line) {
                return playback
            }
            
            // Try text format with patterns like:
            // "Now playing: Artist - Title (album) [duration]"
            // "track_change: {artist: "...", title: "...", album: "...", ...}"
            if let playback = tryParseTextLog(line) {
                return playback
            }
        }
        
        return nil
    }
    
    /// Parse JSON-formatted log entry
    private func tryParseJSONLog(_ line: String) -> YandexLogPlayback? {
        // Remove leading/trailing whitespace
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Extract JSON from log line if present
        guard let startIndex = trimmed.firstIndex(of: "{"),
              let endIndex = trimmed.lastIndex(of: "}") else {
            return nil
        }
        
        let jsonStart = String(trimmed[...startIndex])
        let jsonEnd = String(trimmed[endIndex...])
        let jsonText = jsonStart + jsonEnd
        
        guard let data = jsonText.data(using: .utf8) else { return nil }
        
        do {
            let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let dict = dict else { return nil }
            
            let artist = dict["artist"] as? String ?? dict["title"] as? String ?? ""
            let title = dict["title"] as? String ?? dict["artist"] as? String ?? ""
            let album = dict["album"] as? String
            let duration = (dict["duration"] as? NSNumber)?.intValue ?? 0
            let position = (dict["position"] as? NSNumber)?.doubleValue ?? 0
            let isPlaying = dict["playing"] as? Bool ?? true
            
            return YandexLogPlayback(
                title: title,
                artist: artist,
                album: album,
                duration: duration,
                position: position,
                isPlaying: isPlaying
            )
        } catch {
            return nil
        }
    }
    
    /// Parse text-formatted log entry
    private func tryParseTextLog(_ line: String) -> YandexLogPlayback? {
        // Pattern 1: "Artist - Title (album)"
        let artistTitlePattern = #"(\w[\w\s']+?)\s*[-–]\s*(.+?)(?:\s*\(([^)]+)\))?$"#
        
        // Pattern 2: "track: Artist - Title" or "now playing: Artist - Title"
        let trackPattern = #"(?:track|now_playing|now playing):\s*(.+)$"#i
        
        // Pattern 3: Duration format "Artist - Title - Duration: X:YY"
        let durationPattern = #"(.+?)\s*-\s*(.+?)\s*[-–]\s*(\d+[:\d]+)$"#
        
        // Try different patterns
        let patterns = [artistTitlePattern, trackPattern, durationPattern]
        
        for pattern in patterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            guard let regex = regex else { continue }
            
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range) else { continue }
            
            if match.numberOfRanges >= 3 {
                let artistRange = Range(match.range(at: 1), in: line)!
                let artist = String(line[artistRange]).trimmingCharacters(in: .whitespaces)
                
                let titleRange = Range(match.range(at: 2), in: line)!
                var title = String(line[titleRange]).trimmingCharacters(in: .whitespaces)
                
                // Remove album from title if present
                if match.numberOfRanges >= 4 {
                    let albumRange = Range(match.range(at: 3), in: line)!
                    title = title.replacingOccurrences(of: String(line[albumRange]), with: "", options: [.caseInsensitive])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    title = title.replacingOccurrences(of: " -", with: "")
                        .trimmingCharacters(in: .whitespaces)
                }
                
                // Parse duration if available
                var duration = 0
                if match.numberOfRanges >= 4 {
                    let durationString = String(line[Range(match.range(at: 3), in: line)!])
                    duration = parseDurationString(durationString)
                }
                
                return YandexLogPlayback(
                    title: title,
                    artist: artist,
                    album: nil,
                    duration: duration,
                    position: duration > 0 ? Double(duration) / 2 : 0,
                    isPlaying: true
                )
            }
        }
        
        return nil
    }
    
    /// Parse duration string like "3:45" or "3 мин 45 сек"
    private func parseDurationString(_ text: String) -> Int {
        // Russian format: "3 минут 45 секунд" or "3 мин 45 сек"
        let russianPattern = #"(\d+)\s*(?:минут[а-y]?|мин)\s*(?:(\d+)\s*(?:секунд[а-y]?|сек)?)?"#
        
        // Standard format: "3:45"
        let standardPattern = #"(\d+)[:\s](\d+)"#
        
        for pattern in [russianPattern, standardPattern] {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, range: range) {
                    if match.numberOfRanges >= 2 {
                        let minutes = (match.range(at: 1).location >= 0) ? 
                            (Int(text[Range(match.range(at: 1), in: text)!]) ?? 0) : 0
                        let seconds = (match.range(at: 2).location >= 0) ? 
                            (Int(text[Range(match.range(at: 2), in: text)!]) ?? 0) : 0
                        return minutes * 60 + seconds
                    }
                }
            }
        }
        
        return 0
    }
    
    /// Parse log file content
    private func parseLogFile(at path: String) -> YandexLogPlayback? {
        guard let content = try? String(contentsOfFile: path) else {
            return nil
        }
        return parseLogOutput(content)
    }
}

// MARK: - Extension for string parsing
private extension String {
    func parsingYandexLog() -> YandexLogPlayback? {
        // Implementation would go here
        return nil
    }
}