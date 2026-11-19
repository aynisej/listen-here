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

    var identity: String { "\(artist.lowercased())\u{1f}\(title.lowercased())" }
}

enum YandexMonitorResult {
    case track(YandexPlayback)
    case appNotRunning
    case cannotRead(Int)
    case noWindow
    case noTrackMetadata
}

final class YandexMusicMonitorService {
    var onUpdate: ((YandexMonitorResult) -> Void)?
    private var timer: Timer?
    private var isPolling = false

    static var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    static func requestAccessibilityPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
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
            let result = Self.readYandexPlayer()
            DispatchQueue.main.async {
                self?.isPolling = false
                self?.onUpdate?(result)
            }
        }
    }

    private struct ElementInfo {
        let role: String
        let title: String
        let description: String
        let text: String
        let value: Double?
        let maxValue: Double?
        let children: [ElementInfo]
    }

    private static func readYandexPlayer() -> YandexMonitorResult {
        guard let application = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "ru.yandex.desktop.music"
        }) else { return .appNotRunning }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        var windowsValue: CFTypeRef?
        let windowError = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
        guard windowError == .success else { return .cannotRead(Int(windowError.rawValue)) }
        guard let windows = windowsValue as? [AXUIElement], !windows.isEmpty else { return .noWindow }
        let tree = windows.map { read($0, depth: 0) }
        guard !tree.isEmpty else { return .noWindow }

        let all = tree.flatMap(flatten)
        let player = all.first { node in
            [node.title, node.description, node.text].contains {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare("Плеер") == .orderedSame ||
                $0.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare("Player") == .orderedSame
            }
        }
        let playerNodes = player.map(flatten) ?? all

        let artist = playerNodes
            .filter { $0.role == "AXLink" }
            .compactMap { node -> String? in
                for value in [node.description, node.title, node.text] {
                    if let name = value.matching(#"(?i)^(?:артист|artist)\s*[:—-]?\s*(.+)$"#) { return name }
                }
                return nil
            }
            .first

        let album = playerNodes
            .filter { $0.role == "AXLink" }
            .compactMap { node -> String? in
                for value in [node.description, node.title, node.text] {
                    if let name = value.matching(#"(?i)^(?:альбом|album)\s*[:—-]?\s*(.+)$"#) { return name }
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
                if let parsed = parseDuration(node.text + " " + node.description) {
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

    private static func read(_ element: AXUIElement, depth: Int) -> ElementInfo {
        guard depth < 24 else {
            return ElementInfo(role: "", title: "", description: "", text: "", value: nil, maxValue: nil, children: [])
        }
        let role = attribute(element, kAXRoleAttribute as String) as? String ?? ""
        let title = attribute(element, kAXTitleAttribute as String).flatMap(asText) ?? ""
        let description = attribute(element, kAXDescriptionAttribute as String).flatMap(asText) ?? ""
        let text = attribute(element, kAXValueAttribute as String).flatMap(asText) ?? ""
        let value = (attribute(element, kAXValueAttribute as String) as? NSNumber)?.doubleValue
        let maxValue = (attribute(element, kAXMaxValueAttribute as String) as? NSNumber)?.doubleValue
        let childElements = attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? []
        return ElementInfo(role: role, title: title, description: description, text: text,
                           value: value, maxValue: maxValue,
                           children: childElements.map { read($0, depth: depth + 1) })
    }

    private static func attribute(_ element: AXUIElement, _ key: String) -> Any? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }

    private static func asText(_ value: Any) -> String? {
        if let string = value as? String { return string }
        if let attributed = value as? NSAttributedString { return attributed.string }
        return nil
    }

    private static func flatten(_ node: ElementInfo) -> [ElementInfo] {
        [node] + node.children.flatMap(flatten)
    }

    private static func cleanRepeatedText(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = value.split(whereSeparator: \.isWhitespace)
        guard words.count > 1, words.count.isMultiple(of: 2) else { return value }
        let half = words.count / 2
        if words.prefix(half).elementsEqual(words.suffix(half), by: { $0.caseInsensitiveCompare($1) == .orderedSame }) {
            return words.prefix(half).joined(separator: " ")
        }
        return value
    }

    private static func parseDuration(_ text: String) -> (position: Double, duration: Int)? {
        // Example AX value: "48 секунд. / 6 минут, 32 секунды."
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
        // The accessible timecode has current position and total duration.
        let position = matches.first.map { match in
            let range = Range(match.range(at: 2), in: text)
            return range.flatMap { Double(text[$0]) } ?? 0
        } ?? 0
        return (position, total)
    }
}

private extension String {
    func matching(_ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(startIndex..., in: self)
        guard let match = regex.firstMatch(in: self, range: range), match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: self) else { return nil }
        return String(self[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
