//
//  SleepPreventionManager.swift
//  boringNotch
//

import AppKit
import Foundation
import IOKit.pwr_mgt

final class SleepPreventionManager {
    static let shared = SleepPreventionManager()

    private var sleepAssertionID: IOPMAssertionID?
    private var assertionTimer: Timer?
    private var isUserSessionActive = true

    private init() {
        self.setupWorkspaceNotifications()
    }

    deinit {
        self.releaseSleepAssertion()
        self.assertionTimer?.invalidate()
    }

    func preventSleep() {
        self.assertionTimer?.invalidate()
        self.assertionTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.refreshSleepAssertion()
        }
        self.assertionTimer?.fire()
    }

    func allowSleep() {
        self.assertionTimer?.invalidate()
        self.assertionTimer = nil
        self.releaseSleepAssertion()
    }

    private func refreshSleepAssertion() {
        guard self.isUserSessionActive else { return }

        if let id = self.sleepAssertionID {
            IOPMAssertionRelease(id)
        }

        var assertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithDescription(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            "boring.notch prevents sleep" as CFString,
            nil as CFString?,
            nil as CFString?,
            nil as CFString?,
            8,
            nil as CFString?,
            &assertionID
        )

        if result == kIOReturnSuccess {
            self.sleepAssertionID = assertionID
        }
    }

    private func releaseSleepAssertion() {
        if let id = self.sleepAssertionID {
            IOPMAssertionRelease(id)
            self.sleepAssertionID = nil
        }
    }

    private func setupWorkspaceNotifications() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(self.sessionDidResignActive), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(self.sessionDidBecomeActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    }

    @objc private func sessionDidResignActive() {
        self.isUserSessionActive = false
    }

    @objc private func sessionDidBecomeActive() {
        self.isUserSessionActive = true
    }
}
