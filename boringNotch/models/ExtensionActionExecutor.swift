//
//  ExtensionActionExecutor.swift
//  boringNotch
//
//  Runs one ActionID against the real manager that does the work. Every
//  action has its own named `performXxx` function (matching the
//  `implementedBy` string on its ActionDescriptor in CapabilityRegistry.swift)
//  instead of inlining logic into the switch, so "what backs this action" is
//  always a single, greppable function rather than a case in a big block.
//
//  Actions never throw for a denial the way OS permissions would — there's
//  nothing here that needs the user's permission beyond what the app already
//  holds for its own features. Failures are reported back as
//  `ExtensionActionResult.failed(_:)` (bad/missing payload, no matching
//  device, etc.), not exceptions.
//
//  Prerequisite checks: for every action marked `prerequisiteEligible` in
//  CapabilityRegistry, `currentlyMatches(_:payload:)` reads the same live
//  state its `performXxx` would write, and compares it against the payload
//  instead of applying it. These never mutate anything.
//

import AppKit
import Defaults
import Foundation
import UserNotifications

@MainActor
enum ExtensionActionExecutor {
    static func perform(_ id: ActionID, payload: [String: ExtensionValue]) async -> ExtensionActionResult {
        switch id {
        case .notificationRequest: return await performNotificationRequest(payload)
        case .notificationShowInApp: return performInAppAlertShow(payload)
        case .caffeineSet: return performCaffeineSet(payload)
        case .audioOutputSet: return await performAudioOutputSet(payload)
        case .sneakPeekShow: return performSneakPeekShow(payload)
        case .volumeSet: return performVolumeSet(payload)
        case .brightnessSet: return performBrightnessSet(payload)
        case .appOpen: return performAppOpen(payload)
        case .appQuit: return performAppQuit(payload)
        case .clipboardSetText: return performClipboardSetText(payload)
        case .webcamSet: return performWebcamSet(payload)
        case .mediaPlayPause: return performMediaPlayPause(payload)
        case .mediaNextTrack: return performMediaNextTrack(payload)
        case .mediaPreviousTrack: return performMediaPreviousTrack(payload)
        case .shortcutRun: return performShortcutRun(payload)
        case .aiUsageProviderSet: return performAIUsageProviderSet(payload)
        case .hudReplacementSet: return performHUDReplacementSet(payload)
        case .notchSetTab: return performNotchSetTab(payload)
        case .fanFloorSet: return performFanFloorSet(payload)
        }
    }

    /// Read-only counterpart to `perform`, used to evaluate a rule's
    /// `prerequisites`. Only defined for actions where
    /// `CapabilityRegistry.action(id).prerequisiteEligible` is true —
    /// callers should have already rejected the rest at validation time, so
    /// the `false` fallback here is defensive, not a real code path.
    static func currentlyMatches(_ id: ActionID, payload: [String: ExtensionValue]) -> Bool {
        switch id {
        case .caffeineSet: return caffeineCurrentlyMatches(payload)
        case .webcamSet: return webcamCurrentlyMatches(payload)
        case .hudReplacementSet: return hudReplacementCurrentlyMatches(payload)
        case .aiUsageProviderSet: return aiUsageProviderCurrentlyMatches(payload)
        case .notchSetTab: return notchTabCurrentlyMatches(payload)
        case .audioOutputSet: return audioOutputCurrentlyMatches(payload)
        case .volumeSet: return volumeCurrentlyMatches(payload)
        case .brightnessSet: return brightnessCurrentlyMatches(payload)
        case .clipboardSetText: return clipboardCurrentlyMatches(payload)
        case .appOpen: return appOpenCurrentlyMatches(payload)
        case .appQuit: return appQuitCurrentlyMatches(payload)
        case .mediaPlayPause: return mediaPlayPauseCurrentlyMatches(payload)
        case .fanFloorSet: return fanFloorCurrentlyMatches(payload)
        case .notificationRequest, .notificationShowInApp, .sneakPeekShow,
             .mediaNextTrack, .mediaPreviousTrack, .shortcutRun:
            return false
        }
    }

    // MARK: - Notifications

    static func performNotificationRequest(_ payload: [String: ExtensionValue]) async -> ExtensionActionResult {
        guard let title = payload["title"]?.stringValue else {
            return .failed("Missing \"title\" in payload.")
        }
        let body = payload["body"]?.stringValue ?? ""

        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else {
            return .failed("Notifications are not authorized.")
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "extension.\(UUID().uuidString)", content: content, trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            return .ok()
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func performInAppAlertShow(_ payload: [String: ExtensionValue]) -> ExtensionActionResult {
        guard let title = payload["title"]?.stringValue else {
            return .failed("Missing \"title\" in payload.")
        }
        let message = payload["message"]?.stringValue ?? ""
        let icon = payload["icon"]?.stringValue ?? "bolt.badge.a"
        BoringViewCoordinator.shared.showExtensionAlert(title: title, message: message, icon: icon)
        return .ok()
    }

    // MARK: - Caffeine

    static func performCaffeineSet(_ payload: [String: ExtensionValue]) -> ExtensionActionResult {
        let enabled = payload["enabled"]?.boolValue ?? true
        // Idempotent on purpose: activate() restarts the duration timer even
        // if Caffeine is already on, so a rule re-firing every time its
        // trigger recurs (e.g. tabbing back to Xcode) must not touch it again
        // when it's already in the requested state.
        guard CaffeineManager.shared.isActive != enabled else {
            return .ok("Caffeine already \(enabled ? "on" : "off") \u{2014} nothing to do.")
        }
        if enabled {
            CaffeineManager.shared.activate()
        } else {
            CaffeineManager.shared.deactivate()
        }
        return .ok()
    }

    static func caffeineCurrentlyMatches(_ payload: [String: ExtensionValue]) -> Bool {
        CaffeineManager.shared.isActive == (payload["enabled"]?.boolValue ?? true)
    }

    // MARK: - Audio output

    static func performAudioOutputSet(_ payload: [String: ExtensionValue]) async -> ExtensionActionResult {
        guard let name = payload["deviceName"]?.stringValue else {
            return .failed("Missing \"deviceName\" in payload.")
        }
        let manager = AudioOutputManager.shared

        if let match = manager.outputDevices.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) {
            manager.setDefault(match.id)
            return .ok()
        }
        if let dormant = manager.dormantAirPlayDevices.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) {
            await AirPlayConnector.shared.connect(to: dormant)
            return .ok("Waking \(dormant.name)…")
        }
        return .failed("No output device matching \"\(name)\".")
    }

    static func audioOutputCurrentlyMatches(_ payload: [String: ExtensionValue]) -> Bool {
        guard let name = payload["deviceName"]?.stringValue else { return false }
        let manager = AudioOutputManager.shared
        guard let current = manager.outputDevices.first(where: { $0.id == manager.currentDeviceID }) else {
            return false
        }
        return current.name.localizedCaseInsensitiveContains(name)
    }

    // MARK: - Sneak peek

    static func performSneakPeekShow(_ payload: [String: ExtensionValue]) -> ExtensionActionResult {
        let value = payload["value"]?.doubleValue ?? 0
        let type: SneakContentType
        switch payload["type"]?.stringValue ?? "battery" {
        case "volume": type = .volume
        case "brightness": type = .brightness
        case "backlight": type = .backlight
        case "music": type = .music
        case "download": type = .download
        default: type = .battery
        }
        BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: type, value: CGFloat(value))
        return .ok()
    }

    // MARK: - Volume / Brightness

    static func performVolumeSet(_ payload: [String: ExtensionValue]) -> ExtensionActionResult {
        guard let level = payload["level"]?.doubleValue else {
            return .failed("Missing \"level\" in payload.")
        }
        VolumeManager.shared.setAbsolute(Float32(level))
        return .ok()
    }

    static func volumeCurrentlyMatches(_ payload: [String: ExtensionValue]) -> Bool {
        guard let level = payload["level"]?.doubleValue else { return false }
        return abs(Double(VolumeManager.shared.rawVolume) - level) < 0.01
    }

    static func performBrightnessSet(_ payload: [String: ExtensionValue]) -> ExtensionActionResult {
        guard let level = payload["level"]?.doubleValue else {
            return .failed("Missing \"level\" in payload.")
        }
        BrightnessManager.shared.setAbsolute(value: Float(level))
        return .ok()
    }

    static func brightnessCurrentlyMatches(_ payload: [String: ExtensionValue]) -> Bool {
        guard let level = payload["level"]?.doubleValue else { return false }
        return abs(Double(BrightnessManager.shared.rawBrightness) - level) < 0.01
    }

    // MARK: - Apps

    static func performAppOpen(_ payload: [String: ExtensionValue]) -> ExtensionActionResult {
        guard let bundleId = payload["bundleIdentifier"]?.stringValue,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        else {
            return .failed("Could not find an app with that bundle identifier.")
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        return .ok()
    }

    static func appOpenCurrentlyMatches(_ payload: [String: ExtensionValue]) -> Bool {
        guard let bundleId = payload["bundleIdentifier"]?.stringValue else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
    }

    static func performAppQuit(_ payload: [String: ExtensionValue]) -> ExtensionActionResult {
        guard let bundleId = payload["bundleIdentifier"]?.stringValue else {
            return .failed("Missing \"bundleIdentifier\" in payload.")
        }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        guard !apps.isEmpty else {
            return .failed("\(bundleId) is not running.")
        }
        apps.forEach { $0.terminate() }
        return .ok()
    }

    static func appQuitCurrentlyMatches(_ payload: [String: ExtensionValue]) -> Bool {
        guard let bundleId = payload["bundleIdentifier"]?.stringValue else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
    }

    // MARK: - Clipboard

    static func performClipboardSetText(_ payload: [String: ExtensionValue]) -> ExtensionActionResult {
        guard let text = payload["text"]?.stringValue else {
            return .failed("Missing \"text\" in payload.")
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return .ok()
    }

    static func clipboardCurrentlyMatches(_ payload: [String: ExtensionValue]) -> Bool {
        guard let text = payload["text"]?.stringValue else { return false }
        return NSPasteboard.general.string(forType: .string) == text
    }

    // MARK: - Webcam

    static func performWebcamSet(_ payload: [String: ExtensionValue]) -> ExtensionActionResult {
        let enabled = payload["enabled"]?.boolValue ?? true
        if enabled {
            WebcamManager.shared.startSession()
        } else {
            WebcamManager.shared.stopSession()
        }
        return .ok()
    }

    static func webcamCurrentlyMatches(_ payload: [String: ExtensionValue]) -> Bool {
        WebcamManager.shared.isSessionRunning == (payload["enabled"]?.boolValue ?? true)
    }

    // MARK: - Media

    static func performMediaPlayPause(_ payload: [String: ExtensionValue]) -> ExtensionActionResult {
        // There are three real states here, not two: playing, paused (a
        // track is loaded but stopped), and idle (no active media session
        // at all — source app quit, or nothing has ever played). Acting on
        // play/pause when idle has nothing to act on, so it's guarded the
        // same way regardless of what `playing` asks for.
        guard !MusicManager.shared.isPlayerIdle else {
            return .ok("No active media session \u{2014} nothing to do.")
        }
        let playing = payload["playing"]?.boolValue ?? true
        guard MusicManager.shared.isPlaying != playing else {
            return .ok("Media already \(playing ? "playing" : "paused") \u{2014} nothing to do.")
        }
        if playing {
            MusicManager.shared.play()
        } else {
            MusicManager.shared.pause()
        }
        return .ok()
    }

    static func mediaPlayPauseCurrentlyMatches(_ payload: [String: ExtensionValue]) -> Bool {
        MusicManager.shared.isPlaying == (payload["playing"]?.boolValue ?? true)
    }

    static func performMediaNextTrack(_ payload: [String: ExtensionValue]) -> ExtensionActionResult {
        guard !MusicManager.shared.isPlayerIdle else {
            return .ok("No active media session \u{2014} nothing to do.")
        }
        MusicManager.shared.nextTrack()
        return .ok()
    }

    static func performMediaPreviousTrack(_ payload: [String: ExtensionValue]) -> ExtensionActionResult {
        guard !MusicManager.shared.isPlayerIdle else {
            return .ok("No active media session \u{2014} nothing to do.")
        }
        MusicManager.shared.previousTrack()
        return .ok()
    }

    // MARK: - Shortcuts

    static func performShortcutRun(_ payload: [String: ExtensionValue]) -> ExtensionActionResult {
        guard let name = payload["name"]?.stringValue,
              let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "shortcuts://run-shortcut?name=\(encoded)")
        else {
            return .failed("Missing or invalid \"name\" in payload.")
        }
        NSWorkspace.shared.open(url)
        return .ok()
    }

    // MARK: - Settings

    static func performAIUsageProviderSet(_ payload: [String: ExtensionValue]) -> ExtensionActionResult {
        guard let raw = payload["provider"]?.stringValue else {
            return .failed("Missing \"provider\" in payload.")
        }
        switch raw.lowercased() {
        case "claude": Defaults[.aiUsageProvider] = .claude
        case "chatgpt": Defaults[.aiUsageProvider] = .chatgpt
        default: return .failed("Unknown provider \"\(raw)\". Expected \"claude\" or \"chatgpt\".")
        }
        return .ok()
    }

    static func aiUsageProviderCurrentlyMatches(_ payload: [String: ExtensionValue]) -> Bool {
        guard let raw = payload["provider"]?.stringValue else { return false }
        switch raw.lowercased() {
        case "claude": return Defaults[.aiUsageProvider] == .claude
        case "chatgpt": return Defaults[.aiUsageProvider] == .chatgpt
        default: return false
        }
    }

    static func performHUDReplacementSet(_ payload: [String: ExtensionValue]) -> ExtensionActionResult {
        Defaults[.hudReplacement] = payload["enabled"]?.boolValue ?? true
        return .ok()
    }

    static func hudReplacementCurrentlyMatches(_ payload: [String: ExtensionValue]) -> Bool {
        Defaults[.hudReplacement] == (payload["enabled"]?.boolValue ?? true)
    }

    static func performNotchSetTab(_ payload: [String: ExtensionValue]) -> ExtensionActionResult {
        guard let raw = payload["view"]?.stringValue else {
            return .failed("Missing \"view\" in payload.")
        }
        switch raw.lowercased() {
        case "home": BoringViewCoordinator.shared.currentView = .home
        case "shelf": BoringViewCoordinator.shared.currentView = .shelf
        default: return .failed("Unknown view \"\(raw)\". Expected \"home\" or \"shelf\".")
        }
        return .ok()
    }

    static func notchTabCurrentlyMatches(_ payload: [String: ExtensionValue]) -> Bool {
        guard let raw = payload["view"]?.stringValue else { return false }
        switch raw.lowercased() {
        case "home": return BoringViewCoordinator.shared.currentView == .home
        case "shelf": return BoringViewCoordinator.shared.currentView == .shelf
        default: return false
        }
    }

    // MARK: - Fan floor

    static func performFanFloorSet(_ payload: [String: ExtensionValue]) -> ExtensionActionResult {
        let enabled = payload["enabled"]?.boolValue ?? true
        guard enabled else {
            Defaults[.fanFloorEnabled] = false
            return .ok()
        }
        guard let level = payload["level"]?.doubleValue else {
            return .failed("Missing \"level\" in payload.")
        }
        Defaults[.fanFloorEnabled] = true
        Defaults[.fanFloorLevel] = level
        return .ok()
    }

    static func fanFloorCurrentlyMatches(_ payload: [String: ExtensionValue]) -> Bool {
        let enabled = payload["enabled"]?.boolValue ?? true
        guard enabled else { return !Defaults[.fanFloorEnabled] }
        guard Defaults[.fanFloorEnabled] else { return false }
        guard let level = payload["level"]?.doubleValue else { return true }
        return abs(Defaults[.fanFloorLevel] - level) < 0.01
    }
}
