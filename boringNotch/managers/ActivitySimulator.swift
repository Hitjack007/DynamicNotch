//
//  ActivitySimulator.swift
//  boringNotch
//

import AppKit
import CoreGraphics
import Foundation
import IOKit

final class ActivitySimulator {
    static let shared = ActivitySimulator()

    private var checkTimer: Timer?
    private let idleThreshold: TimeInterval = 90
    private let checkInterval: TimeInterval = 30

    private init() {}

    deinit {
        self.stopMonitoring()
    }

    func startMonitoring() {
        self.stopMonitoring()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.checkTimer = Timer.scheduledTimer(withTimeInterval: self.checkInterval, repeats: true) { [weak self] _ in
                self?.checkAndSimulateIfNeeded()
            }
        }
    }

    func stopMonitoring() {
        self.checkTimer?.invalidate()
        self.checkTimer = nil
    }

    func requestPermission() {
        self.simulateActivity()
    }

    private func checkAndSimulateIfNeeded() {
        guard self.getSystemIdleTime() >= self.idleThreshold else { return }
        self.simulateActivity()
    }

    private func getSystemIdleTime() -> TimeInterval {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &iterator) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return 0 }
        defer { IOObjectRelease(entry) }

        var unmanagedDict: Unmanaged<CFMutableDictionary>?
        guard
            IORegistryEntryCreateCFProperties(entry, &unmanagedDict, kCFAllocatorDefault, 0) == KERN_SUCCESS,
            let dict = unmanagedDict?.takeRetainedValue() as? [String: Any],
            let idleTime = dict["HIDIdleTime"] as? Int64
        else { return 0 }

        return TimeInterval(idleTime) / 1_000_000_000
    }

    private func simulateActivity() {
        let currentPos = NSEvent.mouseLocation
        guard let screenHeight = NSScreen.main?.frame.height else { return }
        let cgPoint = CGPoint(x: currentPos.x, y: screenHeight - currentPos.y)

        // CGEvent.post resets HIDIdleTime; CGWarpMouseCursorPosition does not
        if let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: cgPoint, mouseButton: .left) {
            moveEvent.post(tap: .cghidEventTap)
        }
    }
}
