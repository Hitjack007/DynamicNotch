import AppKit
import Defaults
import Testing
@testable import DynamicNotch

/// Parent for every suite that touches closed-notch sizing or screen-change state. Nested
/// suites inherit `.serialized`, which keeps one suite's simulated screen changes (they post
/// `didChangeScreenParametersNotification`, which every live `NotchViewModel` hears) from
/// landing in the middle of another suite's measurements.
@Suite(.serialized)
enum NotchSizeTests {}

extension NotchSizeTests {
    /// Tests for where the closed notch height comes from (`getClosedNotchSize`) and how it
    /// behaves when the screen lookup it depends on is missing or stale.
    ///
    /// Symptom being chased: closed-notch live activities occasionally draw ~6pt shorter than the
    /// physical notch (32 instead of 38) until the notch is hovered, opened and closed again.
    /// 32 is `Defaults[.nonNotchHeight]`, the height `getClosedNotchSize` returns when it cannot
    /// resolve the screen, and `closedNotchSize` caches whatever it last got.
    @MainActor
    @Suite
    struct ClosedNotchSizeSourceTests {
        private let cache = NSScreenUUIDCache.shared

        /// Wipes whatever a previous test left in the screen cache and rebuilds it from the real screens.
        private func restoreRealScreens() {
            cache.screensProvider = { NSScreen.screens }
            cache.rebuildCache()
        }

        /// Makes the cache rebuild from `screens`, as it does when macOS posts a screen change
        /// while displays are waking, sleeping or reconfiguring.
        private func rebuildCache(from screens: [NSScreen]) {
            cache.screensProvider = { screens }
            cache.rebuildCache()
        }

        private func realScreenUUID() throws -> String {
            try #require(NSScreen.main?.displayUUID, "test host has no main screen")
        }

        /// The height `getClosedNotchSize` returns for a screen it cannot find.
        private var fallbackSize: CGSize { getClosedNotchSize(screenUUID: "no-such-screen") }

        // MARK: - getClosedNotchSize / screen cache

        @Test("Closed size is unchanged when a screen change reports an empty screen list")
        func emptyScreenListKeepsClosedSize() throws {
            restoreRealScreens()
            defer { restoreRealScreens() }
            let uuid = try realScreenUUID()
            let expected = getClosedNotchSize(screenUUID: uuid)
            try #require(expected != fallbackSize, "real size equals the fallback, so this test could not tell them apart")

            rebuildCache(from: [])

            #expect(getClosedNotchSize(screenUUID: uuid) == expected)
        }

        @Test("Screen lookup still finds a real screen after an empty rebuild")
        func lookupSurvivesEmptyRebuild() throws {
            restoreRealScreens()
            defer { restoreRealScreens() }
            let uuid = try realScreenUUID()

            rebuildCache(from: [])

            #expect(NSScreen.screen(withUUID: uuid) != nil)
        }

        // MARK: - NotchViewModel

        @Test("Closing during an empty screen list does not poison closedNotchSize")
        func closeDuringEmptyScreenListKeepsSize() throws {
            restoreRealScreens()
            defer { restoreRealScreens() }
            let uuid = try realScreenUUID()
            let model = NotchViewModel(screenUUID: uuid)
            defer { model.destroy() }
            model.hideOnClosed = false
            let good = model.closedNotchSize
            try #require(good != fallbackSize, "real size equals the fallback, so this test could not tell them apart")

            rebuildCache(from: [])
            model.close()   // what adjustWindowPosition does after a screen change

            #expect(model.closedNotchSize == good)
            #expect(model.effectiveClosedNotchHeight == good.height)
        }

        @Test("A poisoned closed size is repaired by the next screen change, without hovering or opening")
        func screenChangeRepairsPoisonedSize() async throws {
            restoreRealScreens()
            defer { restoreRealScreens() }
            let uuid = try realScreenUUID()
            let model = NotchViewModel(screenUUID: uuid)
            defer { model.destroy() }
            model.hideOnClosed = false
            let good = model.closedNotchSize
            try #require(good != fallbackSize, "real size equals the fallback, so this test could not tell them apart")

            // Force the bad value in, the way an unresolved screen would have.
            model.setClosedLayout(size: fallbackSize)
            restoreRealScreens()
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

            var repaired = false
            for _ in 0..<40 where !repaired {
                try await Task.sleep(for: .milliseconds(25))
                repaired = model.closedNotchSize == good
            }
            #expect(repaired, "closedNotchSize stayed \(model.closedNotchSize) instead of \(good)")
        }

        @Test("Open then close recomputes the size (why hovering appears to fix it)")
        func openCloseRecomputes() throws {
            restoreRealScreens()
            defer { restoreRealScreens() }
            let uuid = try realScreenUUID()
            let model = NotchViewModel(screenUUID: uuid)
            defer { model.destroy() }
            model.hideOnClosed = false
            let good = model.closedNotchSize

            model.setClosedLayout(size: fallbackSize)
            model.open()
            model.close()

            #expect(model.closedNotchSize == good)
        }

        // MARK: - Stress

        /// Each argument drives a different deterministic sequence of screen lists (empty / real)
        /// interleaved with closes and screen-change notifications, wiping the cache first.
        @Test("closedNotchSize survives a random run of transient screen lists", arguments: 1...100)
        func randomScreenListSequence(seed: Int) async throws {
            restoreRealScreens()
            defer { restoreRealScreens() }
            let uuid = try realScreenUUID()
            let model = NotchViewModel(screenUUID: uuid)
            defer { model.destroy() }
            model.hideOnClosed = false
            let good = model.closedNotchSize
            try #require(good != fallbackSize, "real size equals the fallback, so this test could not tell them apart")

            var state = UInt64(seed) &* 6364136223846793005 &+ 1442695040888963407
            func next() -> UInt64 {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return state >> 33
            }

            for step in 0..<12 {
                if next() % 2 == 0 {
                    rebuildCache(from: [])
                } else {
                    restoreRealScreens()
                }
                if next() % 3 == 0 {
                    NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
                    try await Task.sleep(for: .milliseconds(2))
                }
                model.close()
                #expect(model.closedNotchSize == good, "seed \(seed) step \(step)")
            }
        }
    }
}
