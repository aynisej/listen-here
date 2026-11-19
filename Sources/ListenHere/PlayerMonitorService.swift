//
//  PlayerMonitorService.swift
//  Listen Here
//
//  Created by qweq on 18.04.2026.
//

import Foundation

final class PlayerMonitorService {
    private let center = DistributedNotificationCenter.default()
    private var isRunning = false

    var onTrackChange: ((Track) -> Void)?

    func start() {
        guard !isRunning else { return }
        isRunning = true
        // Apple Music
        center.addObserver(
            self,
            selector: #selector(handleMusic),
            name: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil
        )

        // Spotify
        center.addObserver(
            self,
            selector: #selector(handleSpotify),
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil
        )
    }

    func stop() {
        guard isRunning else { return }
        center.removeObserver(self)
        isRunning = false
    }

    @objc private func handleMusic(_ notification: Notification) {
        guard let info = notification.userInfo else { return }

        let track = Track(
            title: info["Name"] as? String ?? "",
            artist: info["Artist"] as? String ?? ""
        )

        onTrackChange?(track)
    }

    @objc private func handleSpotify(_ notification: Notification) {
        guard let info = notification.userInfo else { return }

        let track = Track(
            title: info["Name"] as? String ?? "",
            artist: info["Artist"] as? String ?? ""
        )

        onTrackChange?(track)
    }
}
