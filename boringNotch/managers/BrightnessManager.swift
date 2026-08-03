//  BrightnessManager.swift
//  boringNotch
//
//  Created by JeanLouis on 08/22/24.

import AppKit
import Darwin

final class BrightnessManager: ObservableObject {
	static let shared = BrightnessManager()

	@Published private(set) var rawBrightness: Float = 0
	@Published private(set) var animatedBrightness: Float = 0
	@Published private(set) var lastChangeAt: Date = .distantPast

	private let visibleDuration: TimeInterval = 1.2
	private let client = XPCHelperClient.shared

	private init() { refresh() }

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

	/// Synchronous read of the current display brightness for polling use.
	static func pollCurrentBrightness() -> Float? {
		DisplayServicesAPI.get()
	}

	func refresh() {
		// Prefer direct DisplayServices (main process has the GUI session the API needs).
		if let current = DisplayServicesAPI.get() {
			publish(brightness: current, touchDate: false)
			return
		}
		Task { @MainActor in
			if let current = await client.currentScreenBrightness() {
				publish(brightness: current, touchDate: false)
			}
		}
	}

	@MainActor func setRelative(delta: Float) {
		let current = DisplayServicesAPI.get() ?? rawBrightness
		let target = max(0, min(1, current + delta))

		// Show HUD immediately — no async round-trip needed.
		BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(target))

		if DisplayServicesAPI.set(target) {
			publish(brightness: target, touchDate: true)
		} else {
			// Fallback to XPC helper (e.g. external displays via DDC).
			Task { @MainActor in
				let starting = await client.currentScreenBrightness() ?? current
				let xpcTarget = max(0, min(1, starting + delta))
				if await client.setScreenBrightness(xpcTarget) {
					publish(brightness: xpcTarget, touchDate: true)
					if abs(xpcTarget - target) > 0.02 {
						BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(xpcTarget))
					}
				}
			}
		}
	}

	func setAbsolute(value: Float) {
		let clamped = max(0, min(1, value))
		if DisplayServicesAPI.set(clamped) {
			publish(brightness: clamped, touchDate: true)
			return
		}
		Task { @MainActor in
			if await client.setScreenBrightness(clamped) {
				publish(brightness: clamped, touchDate: true)
			} else {
				refresh()
			}
		}
	}

	private func publish(brightness: Float, touchDate: Bool) {
		DispatchQueue.main.async {
			if self.rawBrightness != brightness || touchDate {
				if touchDate { self.lastChangeAt = Date() }
				self.rawBrightness = brightness
				self.animatedBrightness = brightness
			}
		}
	}
}

// MARK: - DisplayServices direct access
// Must be called from the main GUI process (which owns a window server connection).
// The headless XPC helper lacks that connection, so DisplayServicesSetBrightness
// fails there even if the symbol resolves — this is why we call it here instead.
private enum DisplayServicesAPI {
    private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    static let getFn: GetFn? = handle
        .flatMap { dlsym($0, "DisplayServicesGetBrightness") }
        .map { unsafeBitCast($0, to: GetFn.self) }

    static let setFn: SetFn? = handle
        .flatMap { dlsym($0, "DisplayServicesSetBrightness") }
        .map { unsafeBitCast($0, to: SetFn.self) }

    static func get() -> Float? {
        guard let fn = getFn else { return nil }
        var v: Float = 0
        return fn(CGMainDisplayID(), &v) == 0 ? v : nil
    }

    @discardableResult
    static func set(_ value: Float) -> Bool {
        guard let fn = setFn else { return false }
        return fn(CGMainDisplayID(), value) == 0
    }
}

// MARK: - Keyboard Backlight Controller
final class KeyboardBacklightManager: ObservableObject {
	static let shared = KeyboardBacklightManager()

	@Published private(set) var rawBrightness: Float = 0
	@Published private(set) var lastChangeAt: Date = .distantPast

	private let visibleDuration: TimeInterval = 1.2
	private let client = XPCHelperClient.shared

	private init() { refresh() }

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

	func refresh() {
		Task { @MainActor in
			if let current = await client.currentKeyboardBrightness() {
				publish(brightness: current, touchDate: false)
			}
		}
	}

	@MainActor func setRelative(delta: Float) {
		Task { @MainActor in
			let starting = await client.currentKeyboardBrightness() ?? rawBrightness
			let target = max(0, min(1, starting + delta))
			let ok = await client.setKeyboardBrightness(target)
			if ok {
				publish(brightness: target, touchDate: true)
			} else {
				refresh()
			}
			BoringViewCoordinator.shared.toggleSneakPeek(
				status: true,
				type: .backlight,
				value: CGFloat(target)
			)
		}
	}

	func setAbsolute(value: Float) {
		let clamped = max(0, min(1, value))
		Task { @MainActor in
			let ok = await client.setKeyboardBrightness(clamped)
			if ok {
				publish(brightness: clamped, touchDate: true)
			} else {
				refresh()
			}
		}
	}

	private func publish(brightness: Float, touchDate: Bool) {
		DispatchQueue.main.async {
			if self.rawBrightness != brightness || touchDate {
				if touchDate { self.lastChangeAt = Date() }
				self.rawBrightness = brightness
			}
		}
	}
}

