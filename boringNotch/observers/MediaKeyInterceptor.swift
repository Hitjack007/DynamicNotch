//
//  MediaKeyInterceptor.swift
//  boringNotch
//
//  Created by Alexander on 2025-11-23.

import Foundation
import AppKit
import ApplicationServices
import Defaults
import AVFoundation
import os

// One-line switch: set to true to use .cghidEventTap instead of .cgSessionEventTap.
// This beats OSD.framework's own tap on Sequoia if .cgSessionEventTap proves insufficient.
// Default OFF — change here to test without a larger refactor.
private let SUPPRESS_OSD_USE_HID_TAP = false

private let kSystemDefinedEventType = CGEventType(rawValue: 14)!

// CGSMainConnectionID — re-exported by CoreGraphics from SkyLight.
// Declared private so it doesn't conflict with MacroVisionKit's own binding.
@_silgen_name("CGSMainConnectionID")
private func cgsMainConnectionID() -> Int32

final class MediaKeyInterceptor {
    static let shared = MediaKeyInterceptor()

    private enum NXKeyType: Int {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
        case keyboardBrightnessUp = 21
        case keyboardBrightnessDown = 22
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.app", category: "MediaKeyInterceptor")

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let step: Float = 1.0 / 16.0
    private var audioPlayer: AVAudioPlayer?

    // OSD suppression
    private var osdIdleTimer: DispatchSourceTimer?
    private var osdAggressiveTask: Task<Void, Never>?

    // Cached CoreGraphics handle for dynamic CGS symbol resolution.
    private static let coreGraphicsHandle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)

    private init() {}

    // MARK: - Accessibility
    // CGEvent.tapCreate checks the calling process's TCC entry — must be checked
    // here in the main app, not via the XPC helper (which is a different process).

    func requestAccessibilityAuthorization() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func ensureAccessibilityAuthorization(promptIfNeeded: Bool = false) async -> Bool {
        if AXIsProcessTrusted() { return true }
        if promptIfNeeded {
            requestAccessibilityAuthorization()
            try? await Task.sleep(for: .seconds(1))
        }
        return AXIsProcessTrusted()
    }

    // MARK: - Event Tap

    func start(promptIfNeeded: Bool = false) async {
        logger.fault("start() invoked — eventTap=\(self.eventTap != nil), hudReplacement=\(Defaults[.hudReplacement]), AX=\(AXIsProcessTrusted())")
        guard eventTap == nil else { return }

        guard Defaults[.hudReplacement] else {
            stop()
            return
        }

        let authorized = AXIsProcessTrusted()
        if !authorized {
            if promptIfNeeded {
                let granted = await ensureAccessibilityAuthorization(promptIfNeeded: true)
                guard granted else {
                    logger.error("Accessibility not granted — event tap will not start")
                    return
                }
            } else {
                return
            }
        }

        let tapLevel: CGEventTapLocation = SUPPRESS_OSD_USE_HID_TAP ? .cghidEventTap : .cgSessionEventTap
        let mask: CGEventMask = (1 << kSystemDefinedEventType.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: tapLevel,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, cgEvent, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(cgEvent) }
                let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    interceptor.reenableEventTap()
                    return Unmanaged.passUnretained(cgEvent)
                }
                return interceptor.handleEvent(cgEvent)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        let tapCreated = eventTap != nil
        let tapLevelName = SUPPRESS_OSD_USE_HID_TAP ? "cgHIDEventTap" : "cgSessionEventTap"
        logger.fault("[MediaKeys] CGEventTap created: \(tapCreated ? "yes" : "no", privacy: .public)")
        logger.fault("[MediaKeys] Tap level: \(tapLevelName, privacy: .public)")
        logger.fault("[MediaKeys] IOHIDManager: REMOVED")

        guard let eventTap else {
            logger.error("CGEvent.tapCreate returned nil — Accessibility not granted (AXIsProcessTrusted=\(AXIsProcessTrusted()))")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        logger.fault("Event tap started — bundleID=\(Bundle.main.bundleIdentifier ?? "?", privacy: .public)")

        startOSDSuppressor()
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        stopOSDSuppressor()
    }

    fileprivate func reenableEventTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: - Event Handling

    private func handleEvent(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        guard cgEvent.type != .null else {
            return Unmanaged.passUnretained(cgEvent)
        }

        // Brightness keys from external keyboards arrive as raw keyDown/keyUp
        // events on Sequoia — they bypass the sysDefined path entirely.
        if cgEvent.type == .keyDown || cgEvent.type == .keyUp {
            return handleBrightnessKeyEvent(cgEvent)
        }

        guard let nsEvent = NSEvent(cgEvent: cgEvent),
              nsEvent.type == .systemDefined else {
            return Unmanaged.passUnretained(cgEvent)
        }

        let subtype = nsEvent.subtype.rawValue
        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let stateByte = ((data1 & 0xFF00) >> 8)
        let keyDown = stateByte == 0xA

        logger.fault("NX systemDefined: subtype=\(subtype), keyCode=\(keyCode), state=\(String(format: "0x%X", stateByte))")

        guard subtype == 8 else {
            return Unmanaged.passUnretained(cgEvent)
        }

        guard let keyType = NXKeyType(rawValue: keyCode) else {
            logger.fault("[MediaKeys] sysDefined keyCode=\(keyCode) keyDown=\(keyDown) → no match, passing through")
            return Unmanaged.passUnretained(cgEvent)
        }

        // Swallow keyUp for known keys so BezelServices never receives either half of the pair.
        // Only act on keyDown to avoid double-firing.
        guard keyDown else {
            return nil
        }

        let flags = nsEvent.modifierFlags
        let option = flags.contains(.option)
        let shift = flags.contains(.shift)
        let command = flags.contains(.command)

        logger.fault("[MediaKeys] sysDefined keyCode=\(keyCode) keyDown=true → handling \(String(describing: keyType), privacy: .public)")

        if option && !shift {
            if handleOptionAction(for: keyType, command: command) {
                return nil
            }
        }

        handleKeyPress(keyType: keyType, option: option, shift: shift, command: command)
        return nil
    }

    private func handleBrightnessKeyEvent(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        let rawCode = cgEvent.getIntegerValueField(.keyboardEventKeycode)
        let isBrightnessUp   = rawCode == 0x71 || rawCode == 0x90
        let isBrightnessDown = rawCode == 0x6B || rawCode == 0x91

        guard isBrightnessUp || isBrightnessDown else {
            return Unmanaged.passUnretained(cgEvent)
        }

        if cgEvent.type == .keyUp {
            logger.fault("[Brightness] keyUp keycode=\(String(format: "0x%02X", rawCode)) → swallowed")
            return nil
        }

        // keyDown — apply delta and trigger HUD
        let delta: Float = isBrightnessUp ? step : -step
        logger.fault("[Brightness] keyDown keycode=\(String(format: "0x%02X", rawCode)) → \(isBrightnessUp ? "brightnessUp" : "brightnessDown", privacy: .public) → HUD triggered, event swallowed")

        Task { @MainActor in
            BrightnessManager.shared.setRelative(delta: delta)
        }
        triggerAggressiveOSDCheck()

        return nil
    }

    private func handleOptionAction(for keyType: NXKeyType, command: Bool) -> Bool {
        let action = Defaults[.optionKeyAction]

        switch action {
        case .openSettings:
            openSystemSettings(for: keyType, command: command)
            return true
        case .showHUD:
            showHUD(for: keyType, command: command)
            return true
        case .none:
            return true
        }
    }

    private func prepareAudioPlayerIfNeeded() {
        guard audioPlayer == nil else { return }

        let defaultPath = "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"
        if FileManager.default.fileExists(atPath: defaultPath) {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: defaultPath))
                logger.debug("Loaded Bezel audio from: \(defaultPath, privacy: .public)")
            } catch {
                logger.error("Failed to init AVAudioPlayer at \(defaultPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        } else {
            logger.error("Bezel audio not found at: \(defaultPath, privacy: .public)")
        }

        if let player = audioPlayer {
            player.volume = 1.0
            player.numberOfLoops = 0
            player.prepareToPlay()
        }
    }

    private func playFeedbackSound() {
        guard let feedback = UserDefaults.standard.persistentDomain(forName: "NSGlobalDomain")?["com.apple.sound.beep.feedback"] as? Int,
              feedback == 1 else { return }

        prepareAudioPlayerIfNeeded()
        guard let player = audioPlayer else {
            logger.error("No audio player available to play feedback sound")
            return
        }
        if let url = player.url {
            logger.debug("Playing feedback sound from: \(url.path, privacy: .public)")
        } else {
            logger.debug("Playing feedback sound (AVAudioPlayer has no url)")
        }
        if player.isPlaying {
            player.stop()
            player.currentTime = 0
        }
        player.play()
    }

    private func handleKeyPress(keyType: NXKeyType, option: Bool, shift: Bool, command: Bool) {
        let stepDivisor: Float = (option && shift) ? 4.0 : 1.0

        switch keyType {
        case .soundUp:
            Task { @MainActor in
                self.playFeedbackSound()
                VolumeManager.shared.increase(stepDivisor: stepDivisor)
            }
        case .soundDown:
            Task { @MainActor in
                self.playFeedbackSound()
                VolumeManager.shared.decrease(stepDivisor: stepDivisor)
            }
        case .mute:
            Task { @MainActor in
                VolumeManager.shared.toggleMuteAction()
            }
        case .brightnessUp, .keyboardBrightnessUp:
            let delta = step / stepDivisor
            adjustBrightness(delta: delta, keyboard: keyType == .keyboardBrightnessUp || command)
        case .brightnessDown, .keyboardBrightnessDown:
            let delta = -(step / stepDivisor)
            adjustBrightness(delta: delta, keyboard: keyType == .keyboardBrightnessDown || command)
        }
    }

    private func adjustBrightness(delta: Float, keyboard: Bool) {
        Task { @MainActor in
            if keyboard {
                KeyboardBacklightManager.shared.setRelative(delta: delta)
            } else {
                BrightnessManager.shared.setRelative(delta: delta)
            }
        }
    }

    private func showHUD(for keyType: NXKeyType, command: Bool) {
        Task { @MainActor in
            switch keyType {
            case .soundUp, .soundDown, .mute:
                let v = VolumeManager.shared.rawVolume
                let icon = VolumeManager.shared.bluetoothAudioModel?.sfSymbolName ?? ""
                BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(v), icon: icon)
            case .brightnessUp, .brightnessDown:
                if command {
                    let v = KeyboardBacklightManager.shared.rawBrightness
                    BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .backlight, value: CGFloat(v))
                } else {
                    let v = BrightnessManager.shared.rawBrightness
                    BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(v))
                }
            case .keyboardBrightnessUp, .keyboardBrightnessDown:
                let v = KeyboardBacklightManager.shared.rawBrightness
                BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .backlight, value: CGFloat(v))
            }
        }
    }

    // MARK: - OSD Suppression
    // OSDUIHelper spawns its window slightly after the key event reaches BezelServices.
    // We run a 1-second idle CGWindowList scan that switches to 20ms aggressive mode
    // for 500ms when a brightness key fires to narrow the race window.

    private func startOSDSuppressor() {
        guard osdIdleTimer == nil else { return }
        let queue = DispatchQueue(label: "com.boringnotch.osd-idle", qos: .background)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            self?.checkForOSDWindow()
        }
        timer.resume()
        osdIdleTimer = timer
    }

    private func stopOSDSuppressor() {
        osdIdleTimer?.cancel()
        osdIdleTimer = nil
        osdAggressiveTask?.cancel()
        osdAggressiveTask = nil
    }

    // Launched from handleBrightnessKeyEvent — polls every 20ms for 500ms.
    private func triggerAggressiveOSDCheck() {
        osdAggressiveTask?.cancel()
        osdAggressiveTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<25 {
                guard !Task.isCancelled else { return }
                if self.checkForOSDWindow() { return }
                try? await Task.sleep(nanoseconds: 20_000_000)  // 20ms
            }
            self.logger.fault("[OSD] No OSDUIHelper window found in 500ms window — system may not have shown OSD")
        }
    }

    // Returns true if an OSD window was found and suppression was attempted.
    // Safe to call from any thread — uses only thread-safe CGWindowList and CGS APIs.
    @discardableResult
    private func checkForOSDWindow() -> Bool {
        let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        for window in windowList {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                  ownerName == "OSDUIHelper",
                  let windowNumber = window[kCGWindowNumber as String] as? Int else { continue }
            let windowID = CGWindowID(windowNumber)
            logger.fault("[OSD] OSDUIHelper window detected: id=\(windowID)")
            suppressOSDWindow(windowID)
            return true
        }
        return false
    }

    private func suppressOSDWindow(_ windowID: CGWindowID) {
        let conn = cgsMainConnectionID()

        // Option A — set alpha to 0 (invisible but still composited)
        typealias SetAlphaFn = @convention(c) (Int32, CGWindowID, CGFloat) -> CGError
        if let sym = MediaKeyInterceptor.coreGraphicsHandle.flatMap({ dlsym($0, "CGSSetWindowAlpha") }) {
            let fn = unsafeBitCast(sym, to: SetAlphaFn.self)
            if fn(conn, windowID, 0.0) == .success {
                logger.fault("[OSD] Suppressed via option A (CGSSetWindowAlpha)")
                return
            }
        }
        logger.fault("[OSD] Option A failed, trying option B")

        // Option B — push window level below all screens
        typealias SetLevelFn = @convention(c) (Int32, CGWindowID, Int32) -> CGError
        if let sym = MediaKeyInterceptor.coreGraphicsHandle.flatMap({ dlsym($0, "CGSSetWindowLevel") }) {
            let fn = unsafeBitCast(sym, to: SetLevelFn.self)
            if fn(conn, windowID, Int32.min) == .success {
                logger.fault("[OSD] Suppressed via option B (CGSSetWindowLevel)")
                return
            }
        }
        logger.fault("[OSD] Option B failed, trying option C")

        // Option C — move window off-screen
        typealias MoveWindowFn = @convention(c) (Int32, CGWindowID, UnsafePointer<CGPoint>) -> CGError
        if let sym = MediaKeyInterceptor.coreGraphicsHandle.flatMap({ dlsym($0, "CGSMoveWindow") }) {
            let fn = unsafeBitCast(sym, to: MoveWindowFn.self)
            var offscreen = CGPoint(x: -10000, y: -10000)
            if fn(conn, windowID, &offscreen) == .success {
                logger.fault("[OSD] Suppressed via option C (CGSMoveWindow)")
                return
            }
        }

        logger.fault("[OSD] Suppression failed — all CGS options returned errors")
    }

    private func openSystemSettings(for keyType: NXKeyType, command: Bool) {
        let urlString: String

        switch keyType {
        case .soundUp, .soundDown, .mute:
            urlString = "x-apple.systempreferences:com.apple.preference.sound"
        case .brightnessUp, .brightnessDown:
            if command {
                urlString = "x-apple.systempreferences:com.apple.preference.keyboard"
            } else {
                urlString = "x-apple.systempreferences:com.apple.preference.displays"
            }
        case .keyboardBrightnessUp, .keyboardBrightnessDown:
            urlString = "x-apple.systempreferences:com.apple.preference.keyboard"
        }

        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
