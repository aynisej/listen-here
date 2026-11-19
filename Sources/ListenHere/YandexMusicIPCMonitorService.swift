//
//  YandexMusicIPCMonitorService.swift
//  Listen Here
//
//  IPC-based monitor for Yandex Music player state
//

import Foundation
import Combine

/// Monitor service that receives track information via IPC from modified Yandex Music
@MainActor
final class YandexMusicIPCMonitorService {
    private var callback: ((IPCScrobbleResult) -> Void)?
    private var bridge: IPCScrobbleBridge
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private let lock = NSLock()
    
    init() {
        bridge = IPCScrobbleBridge.shared
    }
    
    /// Set callback for monitor results
    func setCallback(_ callback: @escaping (IPCScrobbleResult) -> Void) {
        lock.lock()
        self.callback = callback
        lock.unlock()
    }
    
    /// Start monitoring Yandex Music via IPC
    func start() {
        lock.lock()
        defer { lock.unlock() }
        
        bridge.setCallback { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleIPCResult(result)
            }
        }
        
        bridge.start()
    }
    
    /// Stop monitoring
    func stop() {
        lock.lock()
        bridge.stop()
        lock.unlock()
    }
    
    /// Handle IPC result and convert to YandexMonitorResult
    private func handleIPCResult(_ result: IPCScrobbleResult) {
        lock.lock()
        defer { lock.unlock() }
        
        callback?(result)
    }
}