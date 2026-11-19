//
//  NSScreen+UUID.swift
//  DynamicNotch
//
//  Created by Mark Greene on 2025-11-21.
//

import AppKit
import CoreGraphics

extension NSScreen {
    /// Returns a persistent UUID for this display
    var displayUUID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) {
            return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
        }
        // Virtual displays (Sidecar, AirPlay) may not have a persistent CGDisplayUUID.
        // Fall back to the numeric display ID so they still receive a notch window.
        return "virtual-\(displayID)"
    }
    
    /// The UUID of the macOS main display (the one with the menu bar), in the same
    /// format as `displayUUID`. This is the "primary" display for settings that
    /// should follow global settings rather than a per-display override.
    static var primaryDisplayUUID: String? {
        let displayID = CGMainDisplayID()
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) {
            return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
        }
        return "virtual-\(displayID)"
    }

    /// Find a screen by its UUID
    @MainActor static func screen(withUUID uuid: String) -> NSScreen? {
        return NSScreenUUIDCache.shared.screen(forUUID: uuid)
    }
    
    /// Get UUID to NSScreen mapping for all screens
    @MainActor static var screensByUUID: [String: NSScreen] {
        return NSScreenUUIDCache.shared.allScreens
    }
}

/// Cache for UUID to NSScreen mappings to avoid repeated lookups
@MainActor
final class NSScreenUUIDCache {
    static let shared = NSScreenUUIDCache()
    
    private var cache: [String: NSScreen] = [:]
    private var observer: Any?

    /// The connected screens. Replaceable so tests can simulate the transient screen lists
    /// macOS reports while displays wake, sleep, connect or reconfigure.
    var screensProvider: () -> [NSScreen] = { NSScreen.screens }

    private init() {
        rebuildCache()
        setupObserver()
    }
    
    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    private func setupObserver() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildCache()
            }
        }
    }
    
    func rebuildCache() {
        var newCache: [String: NSScreen] = [:]

        for screen in screensProvider() {
            if let uuid = screen.displayUUID {
                newCache[uuid] = screen
            }
        }

        // While displays wake, sleep or reconfigure macOS can briefly report no screens at
        // all. Replacing the cache with that would make every screen look disconnected, so
        // a lookup for the built-in display would fail until the next screen change.
        guard !newCache.isEmpty else { return }

        cache = newCache
    }

    func screen(forUUID uuid: String) -> NSScreen? {
        if let screen = cache[uuid] { return screen }

        // The cache is rebuilt asynchronously after a screen change, so a lookup can run
        // before it catches up (e.g. a display that was just connected). Ask the live list.
        guard let screen = screensProvider().first(where: { $0.displayUUID == uuid }) else {
            return nil
        }
        cache[uuid] = screen
        return screen
    }
    
    var allScreens: [String: NSScreen] {
        return cache
    }
}
