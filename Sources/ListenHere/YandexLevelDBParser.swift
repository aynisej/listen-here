//
//  YandexLevelDBParser.swift
//  Listen Here
//
//  Parser for Yandex Music LevelDB files to extract track metadata
//

import Foundation

/// Parses Yandex Music LevelDB SST files to extract track metadata
@MainActor final class YandexLevelDBParser {
    static let shared = YandexLevelDBParser()
    
    /// Yandex Music LevelDB paths
    private let indexedBDBasePath = "/Users/aqshel/Library/Application Support/YandexMusic/IndexedB/"
    private let indexedDBPath = "/Users/aqshel/Library/Application Support/YandexMusic/IndexedDB/"
    private let leveldbPath = "/Users/aqshel/Library/Application Support/YandexMusic/IndexedB/000003.log"
    
    /// Track information extracted from LevelDB
    struct LevelDBTrack: Sendable {
        let trackId: Int
        let title: String?
        let artist: String?
        let album: String?
        let duration: Int?
        let genre: String?
    }
    
    private init() {}
    
    /// Parse all SST files and extract track information
    func parseAllTracks() async -> [String: LevelDBTrack] {
        var tracks: [String: LevelDBTrack] = [:]
        
        // Parse indexedB directory
        if let indexedBTracks = await parseDirectory(indexedBDBasePath) {
            tracks.merge(indexedBTracks) { (_, new) in new }
        }
        
        // Parse indexedDB directory
        if let indexedDBTracks = await parseDirectory(indexedDBPath) {
            tracks.merge(indexedDBTracks) { (_, new) in new }
        }
        
        return tracks
    }
    
    /// Parse a directory for SST files
    private func parseDirectory(_ path: String) async -> [String: LevelDBTrack]? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        
        var tracks: [String: LevelDBTrack] = [:]
        
        // Find SST files
        let fileEnumerator = FileManager.default.enumerator(atPath: path)
        while let fileInfo = fileEnumerator?.nextObject() as? URL {
            if fileInfo.pathExtension == "sst" || fileInfo.pathExtension == "log" {
                let filePath = (fileInfo.deletingLastPathComponent() as NSURL).appendingPathComponent(fileInfo.lastPathComponent)!.path
                let fileTracks = await parseFile(filePath)
                tracks.merge(fileTracks) { (_, new) in new }
            }
        }
        
        return tracks.isEmpty ? nil : tracks
    }
    
    /// Parse a single SST or log file
    private func parseFile(_ filePath: String) async -> [String: LevelDBTrack] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
            return [:]
        }
        
        return parseData(data)
    }
    
    /// Parse binary data from LevelDB file
    private func parseData(_ data: Data) -> [String: LevelDBTrack] {
        var tracks: [String: LevelDBTrack] = [:]
        
        // Convert to string for pattern matching
        guard let text = String(data: data, encoding: .utf8) else {
            return tracks
        }
        
        // Extract track metadata using regex patterns
        // These patterns match the protobuf-encoded JSON strings found in LevelDB
        
        // Pattern for track objects
        let trackPattern = "\"((\\d{6,}))\"\\s*,?\\s*\\{?[\\s\\S]*?\"title\"\\s*:\\s*\"([^\"]+)\"[\\s\\S]*?\"artist\"\\s*:\\s*\\{?[\\s\\S]*?\"name\"\\s*:\\s*\"([^\"]+)\"[\\s\\S]*?\\}?[\\s\\S]*?\"album\"\\s*:\\s*\\{?[\\s\\S]*?\"title\"\\s*:\\s*\"([^\"]+)\"[\\s\\S]*?\\}?[\\s\\S]*?\"duration\"\\s*:\\s*(\\d+)"
        
        if let regex = try? NSRegularExpression(pattern: trackPattern, options: [.caseInsensitive]) {
            let nsRange = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: nsRange)
            
            for match in matches {
                guard let trackIdRange = Range(match.range(at: 1), in: text),
                      let titleRange = Range(match.range(at: 3), in: text),
                      let artistRange = Range(match.range(at: 4), in: text),
                      let albumRange = Range(match.range(at: 5), in: text),
                      let durationRange = Range(match.range(at: 6), in: text) else {
                    continue
                }
                
                let trackIdString = String(text[trackIdRange])
                let title = String(text[titleRange])
                let artist = String(text[artistRange])
                let album = String(text[albumRange])
                let durationStr = String(text[durationRange])
                let duration = Int(durationStr) ?? 0
                
                let trackId = Int(trackIdString) ?? 0
                if trackId > 0 {
                    let levelTrack = LevelDBTrack(
                        trackId: trackId,
                        title: title,
                        artist: artist,
                        album: album,
                        duration: duration,
                        genre: nil
                    )
                    
                    tracks[trackIdString] = levelTrack
                }
            }
        }
        
        // Pattern matching extracts real track data from LevelDB
        // Example format: "title":"Lets Get Lost","artist":{"name":"Pulp"}
        
        return tracks
    }
    
    /// Get current playing track from LevelDB (most recently updated)
    func getCurrentPlayingTrack() async -> LevelDBTrack? {
        // Parse the most recent track from the log file
        // This would be the track with the highest activity
        
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: leveldbPath)) else {
            return nil
        }
        
        let tracks = parseData(data)
        
        // Return the most recent track (or first found)
        return tracks.values.first
    }
    
    /// Resolve track ID to track metadata
    func resolveTrack(trackId: Int) async -> LevelDBTrack? {
        let allTracks = await parseAllTracks()
        return allTracks[String(trackId)]
    }
}