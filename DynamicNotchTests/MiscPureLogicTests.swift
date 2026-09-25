import Testing
import Foundation
import AppKit
import SwiftUI
import KeyboardShortcuts
@testable import DynamicNotch

// MARK: - ActiveDownload

@Suite("ActiveDownload.progress")
struct ActiveDownloadTests {

    @Test("progress is -1 when bytesExpected is unknown (<= 0)")
    func progressIsMinusOneWithUnknownTotal() {
        let download = ActiveDownload(id: UUID(), fileName: "a.zip", browser: .safari, bytesReceived: 10, bytesExpected: 0, startedAt: Date())
        #expect(download.progress == -1)
    }

    @Test("progress is the received/expected ratio, capped at 1.0")
    func progressRatioIsCapped() {
        let halfway = ActiveDownload(id: UUID(), fileName: "a.zip", browser: .safari, bytesReceived: 50, bytesExpected: 100, startedAt: Date())
        #expect(halfway.progress == 0.5)

        let overshot = ActiveDownload(id: UUID(), fileName: "a.zip", browser: .safari, bytesReceived: 150, bytesExpected: 100, startedAt: Date())
        #expect(overshot.progress == 1.0)
    }

    @Test("== compares only id, ignoring byte counts")
    func equalityComparesOnlyID() {
        let id = UUID()
        let a = ActiveDownload(id: id, fileName: "a.zip", browser: .safari, bytesReceived: 10, bytesExpected: 100, startedAt: Date())
        let b = ActiveDownload(id: id, fileName: "a.zip", browser: .safari, bytesReceived: 90, bytesExpected: 100, startedAt: Date())
        #expect(a == b, "Two downloads with the same id are equal even with different byte counts")
    }
}

// MARK: - IdleNotchWidget / AmbientActivity

@Suite("Idle widget and ambient activity raw values")
struct EnumRawValueStabilityTests {

    @Test("IdleNotchWidget raw values are pinned, and label mirrors rawValue")
    func idleNotchWidgetRawValues() {
        #expect(IdleNotchWidget.none.rawValue == "None")
        #expect(IdleNotchWidget.batteryMac.rawValue == "Mac Battery")
        #expect(IdleNotchWidget.bluetooth.rawValue == "Bluetooth")
        #expect(IdleNotchWidget.nextEvent.rawValue == "Next Event")
        #expect(IdleNotchWidget.temperature.rawValue == "Temperature")
        #expect(IdleNotchWidget.aiUsage.rawValue == "AI Usage")
        #expect(IdleNotchWidget.time.rawValue == "Clock")
        for widget in IdleNotchWidget.allCases {
            #expect(widget.label == widget.rawValue)
        }
    }

    @Test("AmbientActivity raw values are pinned, and every case has a unique icon")
    func ambientActivityRawValuesAndIcons() {
        #expect(AmbientActivity.music.rawValue == "Music")
        #expect(AmbientActivity.download.rawValue == "Download")
        #expect(AmbientActivity.face.rawValue == "Face")
        #expect(AmbientActivity.aiUsage.rawValue == "AI Usage")

        let icons = AmbientActivity.allCases.map(\.iconName)
        #expect(Set(icons).count == icons.count, "Each ambient activity should have a distinct icon")
    }
}

// MARK: - ChromeVariant

@Suite("ChromeVariant keychain identifiers")
struct ChromeVariantTests {

    @Test("Each variant has a distinct keychain service and account")
    func keychainIdentifiers() {
        #expect(ChromeVariant.chrome.keychainService == "Chrome Safe Storage")
        #expect(ChromeVariant.chrome.keychainAccount == "Chrome")
        #expect(ChromeVariant.brave.keychainService == "Brave Safe Storage")
        #expect(ChromeVariant.brave.keychainAccount == "Brave")
        #expect(ChromeVariant.edge.keychainService == "Microsoft Edge Safe Storage")
        #expect(ChromeVariant.edge.keychainAccount == "Microsoft Edge")
    }

    @Test("cookiePath is rooted under the user's home directory")
    func cookiePathIsUnderHome() {
        let home = NSHomeDirectory()
        #expect(ChromeVariant.chrome.cookiePath.hasPrefix(home))
        #expect(ChromeVariant.chrome.cookiePath.hasSuffix("Google/Chrome/Default/Cookies"))
    }
}

// MARK: - KeyboardShortcuts.Shortcut

@Suite("KeyboardShortcuts.Shortcut.toEventModifiers")
struct ShortcutModifiersTests {

    @Test("Each NSEvent modifier flag maps to its SwiftUI EventModifiers counterpart")
    func modifierMapping() {
        let shortcut = KeyboardShortcuts.Shortcut(.a, modifiers: [.command, .shift])
        let modifiers = shortcut.toEventModifiers()
        #expect(modifiers.contains(.command))
        #expect(modifiers.contains(.shift))
        #expect(!modifiers.contains(.control))
        #expect(!modifiers.contains(.option))
    }

    @Test("No modifiers maps to an empty set")
    func noModifiersMapsToEmptySet() {
        let shortcut = KeyboardShortcuts.Shortcut(.a, modifiers: [])
        #expect(shortcut.toEventModifiers().isEmpty)
    }
}

// MARK: - ShelfItemExpiry / CalendarSelectionState

@Suite("ShelfItemExpiry and CalendarSelectionState")
struct SettingsEnumTests {

    @Test("timeInterval is nil only for .never, and matches the documented durations otherwise")
    func shelfItemExpiryIntervals() {
        #expect(ShelfItemExpiry.never.timeInterval == nil)
        #expect(ShelfItemExpiry.oneHour.timeInterval == 3_600)
        #expect(ShelfItemExpiry.twoHours.timeInterval == 7_200)
        #expect(ShelfItemExpiry.twentyFourHours.timeInterval == 86_400)
        #expect(ShelfItemExpiry.twoDays.timeInterval == 172_800)
        #expect(ShelfItemExpiry.sevenDays.timeInterval == 604_800)
    }

    @Test("CalendarSelectionState round-trips through JSON for both cases")
    func calendarSelectionStateRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let allData = try encoder.encode(CalendarSelectionState.all)
        guard case .all = try decoder.decode(CalendarSelectionState.self, from: allData) else {
            Issue.record("Expected .all to round-trip as .all")
            return
        }

        let selectedData = try encoder.encode(CalendarSelectionState.selected(["cal-1", "cal-2"]))
        guard case .selected(let ids) = try decoder.decode(CalendarSelectionState.self, from: selectedData) else {
            Issue.record("Expected .selected to round-trip as .selected")
            return
        }
        #expect(ids == ["cal-1", "cal-2"])
    }
}

// MARK: - NSImage

@Suite("NSImage brightness and PNG export")
struct NSImageExtensionsTests {

    private func solidImage(_ color: NSColor, size: NSSize = NSSize(width: 4, height: 4)) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

    @Test("getBrightness is near 1 for white and near 0 for black")
    func getBrightnessForSolidColors() {
        #expect(solidImage(.white).getBrightness() > 0.9)
        #expect(solidImage(.black).getBrightness() < 0.1)
    }

    @Test("getBrightness returns 0 for an image with no drawable representation")
    func getBrightnessForEmptyImage() {
        #expect(NSImage().getBrightness() == 0)
    }

    @Test("pngData() produces data starting with the PNG signature")
    func pngDataHasPNGSignature() throws {
        let data = try #require(solidImage(.red).pngData())
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        #expect(Array(data.prefix(8)) == signature)
    }
}

// MARK: - Color.ensureMinimumBrightness

@Suite("Color.ensureMinimumBrightness")
struct ColorBrightnessTests {

    @Test("A factor outside 0...1 returns the color unchanged")
    func outOfBoundsFactorReturnsSelf() {
        let color = Color(red: 0.2, green: 0.3, blue: 0.4, opacity: 1.0)
        #expect(color.ensureMinimumBrightness(factor: -0.1) == color)
        #expect(color.ensureMinimumBrightness(factor: 1.1) == color)
    }

    @Test("Black has zero perceived brightness, so scaling it produces NaN components")
    func blackProducesNaN() {
        let black = Color(red: 0, green: 0, blue: 0, opacity: 1.0)
        let result = NSColor(black.ensureMinimumBrightness(factor: 0.5)).usingColorSpace(.sRGB)!
        var red: CGFloat = 0
        result.getRed(&red, green: nil, blue: nil, alpha: nil)
        #expect(red.isNaN)
    }

    @Test("A bright color is darkened toward the target factor, not just brightened")
    func brightColorIsDarkened() {
        let white = Color(red: 1, green: 1, blue: 1, opacity: 1.0)
        let result = NSColor(white.ensureMinimumBrightness(factor: 0.5)).usingColorSpace(.sRGB)!
        var red: CGFloat = 0
        result.getRed(&red, green: nil, blue: nil, alpha: nil)
        #expect(abs(red - 0.5) < 0.01)
    }
}
