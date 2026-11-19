import Foundation

/// Alternative monitor service that reads track information from logging output.
struct YandexLogPlayback: Equatable {
    let title: String
    let artist: String
    let album: String?
    let duration: Int
    let position: Double
    let isPlaying: Bool
    
    var identity: String { "\(artist.lowercased())\u{001F}\(title.lowercased())" }
}

enum YandexLogMonitorResult {
    case track(YandexLogPlayback)
    case appNotRunning
    case noData
    case permissionDenied
}

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

private func readFromLog(_ logSource: String) -> YandexLogMonitorResult {
    var playback: YandexLogPlayback?
    
    if logSource.isEmpty {
        playback = readFromSystemLog()
    } else {
        playback = readFromLogFile(logSource)
    }
    
    if let playback = playback {
        return .track(playback)
    }
    
    if isYandexMusicRunning() {
        return .noData
    } else {
        return .appNotRunning
    }
}

private func readFromSystemLog() -> YandexLogPlayback? {
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

private func readFromLogFile(_ path: String) -> YandexLogPlayback? {
    guard FileManager.default.fileExists(atPath: path) else {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let defaultLogPath = cacheDir?.appendingPathComponent("YandexMusic/logs/current.log").path
        
        if let defaultPath = defaultLogPath, FileManager.default.fileExists(atPath: defaultPath) {
            return parseLogFile(at: defaultPath)
        }
        return nil
    }
    
    return parseLogFile(at: path)
}

private func parseLogOutput(_ output: String) -> YandexLogPlayback? {
    let lines = output.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    
    for line in lines.reversed() {
        if let playback = tryParseJSONLog(line) {
            return playback
        }
        if let playback = tryParseTextLog(line) {
            return playback
        }
    }
    
    return nil
}

private func tryParseJSONLog(_ line: String) -> YandexLogPlayback? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    
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

private func tryParseTextLog(_ line: String) -> YandexLogPlayback? {
    let artistTitlePattern = "(\\w[\\w\\s']+?)\\s*[-–]\\s*(.+?)(?:\\s*\\(([^)]+)\\))?$"
    let trackPattern = "(?:track|now_playing|now playing):\\s*(.+)$"
    let durationPattern = "(.+?)\\s*-\\s*(.+?)\\s*[-–]\\s*(\\d+[:\\d]+)$"
    
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
            
            if match.numberOfRanges >= 4 {
                let albumRange = Range(match.range(at: 3), in: line)!
                title = title.replacingOccurrences(of: String(line[albumRange]), with: "", options: [.caseInsensitive])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                title = title.replacingOccurrences(of: " -", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
            
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

private func parseDurationString(_ text: String) -> Int {
    let russianPattern = "(\\d+)\\s*(?:минут[а-я]?|мин)\\s*(?:(\\d+)\\s*(?:секунд[а-я]?|сек)?)?"
    let standardPattern = "(\\d+)[:\\s](\\d+)"
    
    for pattern in [russianPattern, standardPattern] {
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range),
               match.numberOfRanges >= 2 {
                let minutesRange = Range(match.range(at: 1), in: text)
                let secondsRange = Range(match.range(at: 2), in: text)
                
                let minutes = minutesRange.map { Int(text[$0]) ?? 0 } ?? 0
                let seconds = secondsRange.map { Int(text[$0]) ?? 0 } ?? 0
                
                return minutes * 60 + seconds
            }
        }
    }
    
    return 0
}

private func parseLogFile(at path: String) -> YandexLogPlayback? {
    guard let content = try? String(contentsOfFile: path) else {
        return nil
    }
    return parseLogOutput(content)
}

/// Callback type for monitor results (non-Sendable for Thread safety)
typealias YandexLogMonitorCallback = @Sendable (YandexLogMonitorResult) -> Void

/// Monitor for reading track info from logs
final class YandexLoggingMonitorService {
    private var callback: YandexLogMonitorCallback?
    private var timer: Timer?
    private let lock = NSLock()
    private let logSource: String
    
    init(logSource: String = "") {
        self.logSource = logSource
    }
    
    func setCallback(_ callback: @escaping YandexLogMonitorCallback) {
        lock.lock()
        self.callback = callback
        lock.unlock()
    }
    
    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard timer == nil else { return }
        let logSourceCopy = logSource
        let callbackCopy = callback
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [callback] _ in
            DispatchQueue.global(qos: .background).async {
                let result = readFromLog(logSourceCopy)
                Task { @MainActor [callback] in
                    callback?(result)
                }
            }
        }
        DispatchQueue.global(qos: .background).async {
            let result = readFromLog(logSourceCopy)
            Task { @MainActor [callbackCopy] in
                callbackCopy?(result)
            }
        }
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
}