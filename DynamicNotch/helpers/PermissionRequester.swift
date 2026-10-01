//
//  PermissionRequester.swift
//  DynamicNotch
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
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            AppLogger.permissions.notice("Permission request (camera): granted=\(granted)")

        case .calendar:
            do {
                let granted = try await calendarService.requestAccess(to: .event)
                AppLogger.permissions.notice("Permission request (calendar): granted=\(granted)")
            } catch {
                AppLogger.permissions.error("Permission request (calendar) threw, \(type(of: error))")
            }

        case .reminders:
            do {
                let granted = try await calendarService.requestAccess(to: .reminder)
                AppLogger.permissions.notice("Permission request (reminders): granted=\(granted)")
            } catch {
                AppLogger.permissions.error("Permission request (reminders) threw, \(type(of: error))")
            }

        case .accessibility:
            let granted = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
            AppLogger.permissions.notice("Permission request (accessibility): granted=\(granted)")

        case .bluetooth:
            // Initializing CBCentralManager triggers the macOS Bluetooth permission dialog.
            // Keep the reference alive while the dialog is shown.
            bluetoothManager = CBCentralManager(delegate: nil, queue: nil)
            try? await Task.sleep(for: .seconds(1))
            bluetoothManager = nil
            AppLogger.permissions.notice("Permission request (bluetooth): dialog triggered")

        case .screenRecording:
            // SCShareableContent access triggers the macOS Screen Recording permission prompt.
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                AppLogger.permissions.notice("Permission request (screen recording): granted")
            } catch {
                AppLogger.permissions.notice("Permission request (screen recording): not granted, \(type(of: error))")
            }
            try? await Task.sleep(for: .seconds(1))

        case .fullDiskAccess:
            AppLogger.permissions.notice("Permission request (full disk access): opened System Settings")
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
            )
        }
    }
}
