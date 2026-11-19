import AppKit
import ApplicationServices
import Foundation

struct YandexPlayback: Equatable {
    let title: String
    let artist: String
    let album: String?
    let duration: Int
    let position: Double
    let isPlaying: Bool

    var identity: String { "\(artist.lowercased())\u{001F}\(title.lowercased())" }
}

enum YandexMonitorResult {
    case track(YandexPlayback)
    case appNotRunning
    case cannotRead(Int)
    case noWindow
    case noTrackMetadata
}

/// Helper to safely access AX elements
private struct AXElementInfo {
    let role: String
    let title: String
    let description: String
    let text: String
    let value: Double?
    let maxValue: Double?
    let children: [AXElementInfo]
}

private func readAXElement(_ element: AXUIElement, depth: Int) -> AXElementInfo {
    guard depth < 24 else {
        return AXElementInfo(role: "", title: "", description: "", text: "", value: nil, maxValue: nil, children: [])
    }
    let role = AXCopyAttribute(element, kAXRoleAttribute as String) as? String ?? ""
    let title = AXCopyAttribute(element, kAXTitleAttribute as String).flatMap({ asText($0) }) ?? ""
    let description = AXCopyAttribute(element, kAXDescriptionAttribute as String).flatMap({ asText($0) }) ?? ""
    let text = AXCopyAttribute(element, kAXValueAttribute as String).flatMap({ asText($0) }) ?? ""
    let value = (AXCopyAttribute(element, kAXValueAttribute as String) as? NSNumber)?.doubleValue
    let maxValue = (AXCopyAttribute(element, kAXMaxValueAttribute as String) as? NSNumber)?.doubleValue
    let childElements = AXCopyAttribute(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? []
    return AXElementInfo(role: role, title: title, description: description, text: text,
                         value: value, maxValue: maxValue,
                         children: childElements.map { readAXElement($0, depth: depth + 1) })
}

private func AXCopyAttribute(_ element: AXUIElement, _ key: String) -> Any? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
    return result
}

private func asText(_ value: Any) -> String? {
    if let string = value as? String { return string }
    if let attributed = value as? NSAttributedString { return attributed.string }
    return nil
}

private func flattenAXNode(_ node: AXElementInfo) -> [AXElementInfo] {
    [node] + node.children.flatMap(flattenAXNode)
}

private func cleanRepeatedText(_ raw: String) -> String {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let words = value.split(whereSeparator: \.isWhitespace)
    guard words.count > 1, words.count.isMultiple(of: 2) else { return value }
    let half = words.count / 2
    if words.prefix(half).elementsEqual(words.suffix(half), by: { $0.caseInsensitiveCompare($1) == .orderedSame }) {
        return words.prefix(half).joined(separator: " ")
    }
    return value
}

private func parseAXDuration(_ text: String) -> (position: Double, duration: Int)? {
    let expression = #"(?:(\d+)\s*(?:минут[аы]?\s*)?)?(\d+)\s*секунд"#
    guard let regex = try? NSRegularExpression(pattern: expression, options: [.caseInsensitive]) else { return nil }
    let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    guard let match = matches.last else { return nil }
    func number(_ index: Int) -> Int {
        guard index < match.numberOfRanges, let range = Range(match.range(at: index), in: text) else { return 0 }
        return Int(text[range]) ?? 0
    }
    let seconds = number(2)
    let minutes = number(1)
    let total = minutes * 60 + seconds
    guard total > 0 else { return nil }
    let position = matches.first.flatMap { match in
        guard let range = Range(match.range(at: 2), in: text) else { return nil }
        return Double(text[range])
    } ?? 0
    return (position, total)
}

private func getStringMatching(_ text: String, _ pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
          let valueRange = Range(match.range(at: 1), in: text) else { return nil }
    return String(text[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func readYandexPlayer() -> YandexMonitorResult {
    guard let application = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == "ru.yandex.desktop.music"
    }) else { return .appNotRunning }

    let appElement = AXUIElementCreateApplication(application.processIdentifier)
    var windowsValue: CFTypeRef?
    let windowError = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
    guard windowError == .success else { return .cannotRead(Int(windowError.rawValue)) }
    guard let windows = windowsValue as? [AXUIElement], !windows.isEmpty else { return .noWindow }
    let tree = windows.map { readAXElement($0, depth: 0) }
    guard !tree.isEmpty else { return .noWindow }

    let all = tree.flatMap(flattenAXNode)
    let player = all.first { node in
        [node.title, node.description, node.text].contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare("Плеер") == .orderedSame ||
            $0.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare("Player") == .orderedSame
        }
    }
    let playerNodes = player.map(flattenAXNode) ?? all

    let artist = playerNodes
        .filter { $0.role == "AXLink" }
        .compactMap { node -> String? in
            for value in [node.description, node.title, node.text] {
                if let name = getStringMatching(value, #"(?i)^(?:артист|artist)\s*[:—-]?\s*(.+)$"#) { return name }
            }
            return nil
        }
        .first

    let album = playerNodes
        .filter { $0.role == "AXLink" }
        .compactMap { node -> String? in
            for value in [node.description, node.title, node.text] {
                if let name = getStringMatching(value, #"(?i)^(?:альбом|album)\s*[:—-]?\s*(.+)$"#) { return name }
            }
            return nil
        }
        .first

    let titleCandidates = playerNodes.compactMap { node -> String? in
        guard node.role == (kAXStaticTextRole as String) || node.role == (kAXTextFieldRole as String) else { return nil }
        let text = cleanRepeatedText(node.text.isEmpty ? node.title : node.text)
        guard !text.isEmpty,
              text.count > 1,
              !text.localizedCaseInsensitiveContains("артист"),
              !text.localizedCaseInsensitiveContains("альбом"),
              !text.localizedCaseInsensitiveContains("плеер"),
              !text.localizedCaseInsensitiveContains("player") else { return nil }
        return text
    }

    guard let title = titleCandidates.max(by: { $0.count < $1.count }),
          let artist, !artist.isEmpty else { return .noTrackMetadata }

    let sliders = playerNodes.filter { $0.role == (kAXSliderRole as String) }
    let slider = sliders.first {
        ($0.description + " " + $0.title).localizedCaseInsensitiveContains("таймкод") ||
        ($0.description + " " + $0.title).localizedCaseInsensitiveContains("progress")
    } ?? sliders.first
    var duration = Int(slider?.maxValue ?? 0)
    var position = slider?.value ?? 0
    if duration <= 0 {
        for node in playerNodes {
            if let parsed = parseAXDuration(node.text + " " + node.description) {
                position = parsed.position
                duration = parsed.duration
                break
            }
        }
    }

    let isPlaying = all.contains { node in
        let label = (node.title + " " + node.description + " " + node.text).lowercased()
        return node.role == (kAXButtonRole as String) &&
            (label.contains("пауза") || label.contains("pause"))
    }
    guard duration > 0 else { return .noTrackMetadata }

    return .track(YandexPlayback(title: title, artist: artist, album: album,
                                 duration: duration, position: max(0, position), isPlaying: isPlaying))
}

/// Callback type for monitor results (non-Sendable for Thread safety)
typealias YandexMonitorCallback = @Sendable (YandexMonitorResult) -> Void

/// Monitor for Yandex Music using Accessibility API
final class YandexMusicMonitorService {
    private var callback: YandexMonitorCallback?
    private var timer: Timer?
    private let lock = NSLock()

    static var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    /// Request Accessibility permission. Returns whether the app is already trusted.
    static func requestAccessibilityPermission() -> Bool {
        // Always return current trust status - the system will prompt automatically
        // when Accessibility APIs are first used, if needed.
        return AXIsProcessTrusted()
    }

    func setCallback(_ callback: @escaping YandexMonitorCallback) {
        lock.lock()
        self.callback = callback
        lock.unlock()
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [callback] _ in
            let result = readYandexPlayer()
            Task { @MainActor [callback] in
                callback?(result)
            }
        }
        // Initial poll
        DispatchQueue.global(qos: .utility).async { [callback] in
            let result = readYandexPlayer()
            Task { @MainActor [callback] in
                callback?(result)
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