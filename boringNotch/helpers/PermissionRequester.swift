//
//  PermissionRequester.swift
//  boringNotch
//
//  Created by Mark Greene on 2026-09-20.
//

import AppKit
import AVFoundation
import CoreBluetooth
import ScreenCaptureKit

/// Extracted from OnboardingView so the same permission prompts can be
/// triggered from a What's New highlight action without duplicating them.
enum PermissionRequester {
    enum Kind {
        case camera
        case calendar
        case reminders
        case accessibility
        case bluetooth
        case screenRecording
        case fullDiskAccess
    }

    private static let calendarService = CalendarService()
    private static var bluetoothManager: CBCentralManager?

    static func request(_ kind: Kind) async {
        switch kind {
        case .camera:
            await AVCaptureDevice.requestAccess(for: .video)

        case .calendar:
            _ = try? await calendarService.requestAccess(to: .event)

        case .reminders:
            _ = try? await calendarService.requestAccess(to: .reminder)

        case .accessibility:
            _ = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)

        case .bluetooth:
            // Initializing CBCentralManager triggers the macOS Bluetooth permission dialog.
            // Keep the reference alive while the dialog is shown.
            bluetoothManager = CBCentralManager(delegate: nil, queue: nil)
            try? await Task.sleep(for: .seconds(1))
            bluetoothManager = nil

        case .screenRecording:
            // SCShareableContent access triggers the macOS Screen Recording permission prompt.
            _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            try? await Task.sleep(for: .seconds(1))

        case .fullDiskAccess:
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
            )
        }
    }
}
