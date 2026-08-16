//
//  CaffeineManager.swift
//  boringNotch
//

import AppKit
import Combine
import Defaults
import Foundation

@MainActor
final class CaffeineManager: ObservableObject {
    static let shared = CaffeineManager()

    @Published private(set) var isActive = false
    @Published private(set) var timeRemaining: TimeInterval?

    private var timeoutTimer: Timer?
    private var displayTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.setupObservers()
    }

    func toggle() {
        if self.isActive {
            self.deactivate()
        } else {
            self.activate()
        }
    }

    func activate() {
        let durationSeconds = Defaults[.caffeineDefaultDuration]
        let duration: TimeInterval? = durationSeconds > 0 ? TimeInterval(durationSeconds) : nil

        self.cancelTimers()

        if let duration {
            self.timeRemaining = duration

            self.timeoutTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                DispatchQueue.main.async { self?.deactivate() }
            }

            self.displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, let timeoutTimer = self.timeoutTimer else {
                        self?.displayTimer?.invalidate()
                        return
                    }
                    self.timeRemaining = max(0, timeoutTimer.fireDate.timeIntervalSinceNow)
                    if self.timeRemaining ?? 0 <= 0 {
                        self.displayTimer?.invalidate()
                        self.displayTimer = nil
                    }
                }
            }
        } else {
            self.timeRemaining = nil
        }

        self.isActive = true
        SleepPreventionManager.shared.preventSleep()

        if Defaults[.caffeineKeepAppsActive] {
            ActivitySimulator.shared.startMonitoring()
        }
    }

    func deactivate() {
        self.cancelTimers()
        self.timeRemaining = nil
        self.isActive = false
        SleepPreventionManager.shared.allowSleep()
        ActivitySimulator.shared.stopMonitoring()
    }

    func updateActivitySimulation(enabled: Bool) {
        if enabled {
            ActivitySimulator.shared.requestPermission()
        }
        if enabled, self.isActive {
            ActivitySimulator.shared.startMonitoring()
        } else {
            ActivitySimulator.shared.stopMonitoring()
        }
    }

    private func setupObservers() {
        // Always deactivate when the Mac sleeps — doesn't matter if it's lid close, menu, etc.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.deactivate() }
            }
            .store(in: &self.cancellables)

        // Run-loop timers pause during sleep; check on wake if the period already elapsed
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self, let timeoutTimer = self.timeoutTimer else { return }
                    if timeoutTimer.fireDate.timeIntervalSinceNow <= 0 {
                        self.deactivate()
                    }
                }
            }
            .store(in: &self.cancellables)
    }

    private func cancelTimers() {
        self.timeoutTimer?.invalidate()
        self.timeoutTimer = nil
        self.displayTimer?.invalidate()
        self.displayTimer = nil
    }
}
