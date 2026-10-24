//
//  DynamicNotchSkyLightWindow.swift
//  DynamicNotch
//
//  Created by Mark Greene on 2025-10-20.
//

import Cocoa
import SkyLightWindow
import Defaults
import Combine

extension SkyLightOperator {
    func undelegateWindow(_ window: NSWindow) {
        typealias F_SLSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32
        
        let handler = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
        guard let SLSRemoveWindowsFromSpaces = unsafeBitCast(
            dlsym(handler, "SLSRemoveWindowsFromSpaces"),
            to: F_SLSRemoveWindowsFromSpaces?.self
        ) else {
            return
        }
        
        // Remove the window from the SkyLight space
        _ = SLSRemoveWindowsFromSpaces(
            connection,
            [window.windowNumber] as CFArray,
            [space] as CFArray
        )
    }
}

class DynamicNotchSkyLightWindow: NSPanel {
    private var isSkyLightEnabled: Bool = false
    
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        
        configureWindow()
        setupObservers()
    }
    
    private func configureWindow() {
        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        level = .mainMenu + 3
        hasShadow = false
        isReleasedWhenClosed = false
        
        // Force dark appearance regardless of system setting
        appearance = NSAppearance(named: .darkAqua)
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        
        // Apply initial sharing type setting
        updateSharingType()
    }
    
    private func setupObservers() {
        // Listen for changes to the hideFromScreenRecording setting
        Defaults.publisher(.hideFromScreenRecording)
            .sink { [weak self] _ in
                self?.updateSharingType()
            }
            .store(in: &observers)
    }
    
    private func updateSharingType() {
        if Defaults[.hideFromScreenRecording] {
            sharingType = .none
        } else {
            sharingType = .readOnly
        }
    }
    
    func enableSkyLight() {
        if !isSkyLightEnabled {
            SkyLightOperator.shared.delegateWindow(self)
            isSkyLightEnabled = true
        }
    }
    
    func disableSkyLight() {
        if isSkyLightEnabled {
            SkyLightOperator.shared.undelegateWindow(self)
            isSkyLightEnabled = false
        }
    }
    
    private var observers: Set<AnyCancellable> = []
    
    // Liquid Glass renders flat and frosted in a window that is never key (faking the key
    // state doesn't work). So while the notch shows glass it becomes the real key window,
    // without activating the app. That would swallow typing meant for the frontmost app, so
    // the first key event gives key status back and is passed on to that app.
    private var glassActive = false

    private var pendingRelease: DispatchWorkItem?

    /// `releaseDelay` postpones giving up key status, so the glass keeps its active look for
    /// a moment while the notch closes. Typing in that gap is still handed back by `sendEvent`.
    func setGlassActive(_ active: Bool, releaseDelay: TimeInterval = 0) {
        pendingRelease?.cancel()
        pendingRelease = nil

        if active {
            glassActive = true
            // Never take key from another of our own windows (Settings, onboarding...), or
            // it would be left looking inactive.
            if let other = NSApp.keyWindow, other !== self, !(other is DynamicNotchSkyLightWindow) {
                return
            }
            makeKey()
        } else if releaseDelay > 0 {
            let item = DispatchWorkItem { [weak self] in self?.releaseKeyNow() }
            pendingRelease = item
            DispatchQueue.main.asyncAfter(deadline: .now() + releaseDelay, execute: item)
        } else {
            releaseKeyNow()
        }
    }

    private func releaseKeyNow() {
        glassActive = false
        if isKeyWindow {
            resignKey()
        }
    }

    /// Makes every notch panel give up key status. Call this before presenting a regular
    /// window from the notch, so that window can activate and become key cleanly.
    static func releaseGlassKey() {
        for window in NSApp.windows.compactMap({ $0 as? DynamicNotchSkyLightWindow }) {
            window.setGlassActive(false)
        }
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown, .keyUp, .flagsChanged:
            guard glassActive else { break }
            glassActive = false
            resignKey()
            // Posting to another app needs Accessibility; without it this one keystroke is dropped.
            if AXIsProcessTrusted(),
               let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
               pid != ProcessInfo.processInfo.processIdentifier {
                event.cgEvent?.postToPid(pid)
            }
            return
        default:
            break
        }
        super.sendEvent(event)
    }

    override var canBecomeKey: Bool { glassActive }
    override var canBecomeMain: Bool { false }
}
