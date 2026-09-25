import Testing
import Foundation
import CoreGraphics
@testable import DynamicNotch

// MARK: - Double/CGFloat rounding helpers

@Suite("Double/CGFloat rounding and truncation helpers")
struct NumericExtensionsTests {

    @Test("evenInt rounds to the nearest integer, then nudges odd results up by one", arguments: [
        (2.4, 2), (2.5, 4), (3.0, 4), (-3.0, -4), (4.0, 4), (0.0, 0),
    ])
    func evenIntRounding(input: Double, expected: Int) {
        #expect(input.evenInt == expected)
    }

    @Test("intround rounds half away from zero")
    func introundRoundsHalfAwayFromZero() {
        #expect((2.5).intround == 3)
        #expect((-2.5).intround == -3)
    }

    @Test("i truncates toward zero rather than rounding")
    func iTruncatesTowardZero() {
        #expect((2.9).i == 2)
        #expect((-2.9).i == -2)
    }

    @Test("CGFloat has the same evenInt/intround/i behavior as Double")
    func cgFloatMatchesDouble() {
        let value: CGFloat = 2.5
        #expect(value.evenInt == 4)
        #expect(value.intround == 3)
        #expect(value.i == 2)
    }
}

// MARK: - NSSize

@Suite("NSSize helpers")
struct NSSizeExtensionsTests {

    @Test("s formats width×height using truncated integers")
    func sFormatsWidthByHeight() {
        #expect(NSSize(width: 1920.6, height: 1080.9).s == "1920×1080")
    }

    @Test("aspectRatio divides width by height, and a zero height gives infinity")
    func aspectRatioAndZeroHeight() {
        #expect(NSSize(width: 1920, height: 1080).aspectRatio == 1920.0 / 1080.0)
        #expect(NSSize(width: 100, height: 0).aspectRatio.isInfinite)
    }

    @Test("scaled(by:) scales both dimensions and rounds each to an even integer")
    func scaledByFactor() {
        let scaled = NSSize(width: 100, height: 50).scaled(by: 1.5)
        #expect(scaled.width == 150) // (100 * 1.5).evenInt == 150.evenInt == 150 (already even)
        #expect(scaled.height == 76) // (50 * 1.5).evenInt == 75.evenInt == 76
    }
}

// MARK: - Date

@Suite("Date day boundary helpers")
struct DateExtensionsTests {

    @Test("noon sets the time to 12:00:00 on the same calendar day")
    func noonSetsTimeToNoon() {
        let calendar = Calendar.current
        let now = Date()
        let noon = now.noon
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: noon)
        #expect(components.hour == 12)
        #expect(components.minute == 0)
        #expect(components.second == 0)
        #expect(calendar.isDate(now, inSameDayAs: noon))
    }

    @Test("dayBefore/dayAfter move exactly one calendar day from noon")
    func dayBeforeAndDayAfter() {
        let calendar = Calendar.current
        let now = Date()
        let before = now.dayBefore
        let after = now.dayAfter

        let daysBefore = calendar.dateComponents([.day], from: before, to: now.noon).day
        let daysAfter = calendar.dateComponents([.day], from: now.noon, to: after).day

        #expect(daysBefore == 1)
        #expect(daysAfter == 1)
    }
}
