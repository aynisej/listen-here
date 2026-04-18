//
//  AppState.swift
//  Listen Here
//
//  Created by qweq on 18.04.2026.
//

import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var statusText: String = "Связь с UI работает"
    @Published var currentTrack: Track?
    private var lastTrack: Track?
    private var scrobbleTimer: Timer?

    private let playerMonitor = PlayerMonitorService()

    init() {
        playerMonitor.onTrackChange = { [weak self] track in
            guard let self else { return }

            // фильтр дублей
            if self.lastTrack == track {
                return
            }

            self.lastTrack = track

            // сброс старого таймера
            self.scrobbleTimer?.invalidate()

            DispatchQueue.main.async {
                self.currentTrack = track
                self.statusText = "Играет (ожидание скроббла)"
            }

            // ⏱️ пока берём фикс 30 секунд
            self.scrobbleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.statusText = "Готов к скробблу"
                    print("SCROBBLE:", track.artist, "-", track.title)
                }
            }
        }

        playerMonitor.start()
    }
}
