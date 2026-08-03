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

// One-line switch: set to true to use .cgHIDEventTap instead of .cgSessionEventTap.
// This beats OSD.framework's own tap on Sequoia if .cgSessionEventTap proves insufficient.
// Default OFF — change here to test without a larger refactor.
private let SUPPRESS_OSD_USE_HID_TAP = false

private let kSystemDefinedEventType = CGEventType(rawValue: 14)!

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

    // Brightness polling state — all accessed on main thread only.
    private var brightnessPoller: DispatchSourceTimer?
    private var lastKnownBrightness: Float = -1
    private var programmaticBrightnessChange = false

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
        let mask = CGEventMask(1 << kSystemDefinedEventType.rawValue)
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
        logger.fault("[MediaKeys] Brightness polling: starting at 20Hz")
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

        startBrightnessPolling()
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
        stopBrightnessPolling()
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
        // Mark as programmatic before the async dispatch so the brightness poller
        // (which also runs on main) ignores the resulting value change.
        programmaticBrightnessChange = true
        Task { @MainActor in
            if keyboard {
                KeyboardBacklightManager.shared.setRelative(delta: delta)
            } else {
                BrightnessManager.shared.setRelative(delta: delta)
            }
            // Clear the flag after the poller has had one cycle to record the new value.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.programmaticBrightnessChange = false
            }
        }
    }

    private func showHUD(for keyType: NXKeyType, command: Bool) {
        Task { @MainActor in
            switch keyType {
            case .soundUp, .soundDown, .mute:
                let v = VolumeManager.shared.rawVolume
                BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(v))
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

    // MARK: - Brightness Polling
    // External keyboard brightness keys on Sequoia bypass CGEventTap entirely —
    // they go direct from HID to BezelServices, generating zero CGEvents.
    // We poll DisplayServices at 20Hz to detect changes we didn't initiate and
    // show our HUD alongside the system OSD (suppression requires private OSD.framework APIs).

    private func startBrightnessPolling() {
        guard brightnessPoller == nil else { return }

        // Seed on the calling (main) thread so the first poll doesn't false-trigger.
        lastKnownBrightness = BrightnessManager.pollCurrentBrightness() ?? -1

        let queue = DispatchQueue(label: "com.boringnotch.brightness-poll", qos: .utility)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(50), repeating: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            // Dispatch to main so all state reads/writes stay on one thread.
            DispatchQueue.main.async { self?.pollBrightness() }
        }
        timer.resume()
        brightnessPoller = timer
        logger.fault("[MediaKeys] Brightness polling: active at 20Hz")
    }

    private func stopBrightnessPolling() {
        brightnessPoller?.cancel()
        brightnessPoller = nil
    }

    private func pollBrightness() {
        guard let current = BrightnessManager.pollCurrentBrightness() else { return }

        let last = lastKnownBrightness
        let delta = abs(current - last)

        guard delta > 0.01 else { return }

        lastKnownBrightness = current

        if programmaticBrightnessChange {
            logger.fault("[Brightness] polled=\(current) last=\(last) delta=\(delta) → ignored (programmatic change)")
            return
        }

        logger.fault("[Brightness] polled=\(current) last=\(last) delta=\(delta) → HUD triggered")
        Task { @MainActor in
            BrightnessManager.shared.refresh()
            BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(current))
        }
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
