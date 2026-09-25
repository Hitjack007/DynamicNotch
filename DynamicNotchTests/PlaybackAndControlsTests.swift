import Testing
import Foundation
@testable import DynamicNotch

// MARK: - PlaybackState

@Suite("PlaybackState equality")
struct PlaybackStateTests {

    @Test("== ignores playbackRate, lastUpdated and volume")
    func equalityIgnoresRateLastUpdatedAndVolume() {
        var a = PlaybackState(bundleIdentifier: "com.example.a")
        var b = PlaybackState(bundleIdentifier: "com.example.a")
        a.playbackRate = 1.0
        b.playbackRate = 2.0
        a.lastUpdated = Date.distantPast
        b.lastUpdated = Date()
        a.volume = 0.1
        b.volume = 0.9
        #expect(a == b, "playbackRate, lastUpdated and volume should not affect equality")
    }

    @Test("== compares artwork and every other tracked field")
    func equalityComparesTrackedFields() {
        var a = PlaybackState(bundleIdentifier: "com.example.a")
        var b = PlaybackState(bundleIdentifier: "com.example.a")
        #expect(a == b)

        b.artwork = Data([1, 2, 3])
        #expect(a != b, "Different artwork should make the states unequal")

        a.artwork = Data([1, 2, 3])
        #expect(a == b)

        b.title = "Different"
        #expect(a != b)
    }

    @Test("RepeatMode raw values are stable")
    func repeatModeRawValues() {
        #expect(RepeatMode.off.rawValue == 1)
        #expect(RepeatMode.one.rawValue == 2)
        #expect(RepeatMode.all.rawValue == 3)
    }
}

// MARK: - MusicControlButton

@Suite("MusicControlButton layout and metadata")
struct MusicControlButtonTests {

    @Test("defaultLayout's slot count is within the configured min/max bounds")
    func defaultLayoutWithinBounds() {
        #expect(MusicControlButton.defaultLayout.count >= MusicControlButton.minSlotCount)
        #expect(MusicControlButton.defaultLayout.count <= MusicControlButton.maxSlotCount)
    }

    @Test("pickerOptions excludes .none and contains every other case exactly once")
    func pickerOptionsExcludesNone() {
        #expect(!MusicControlButton.pickerOptions.contains(.none))
        let expected = Set(MusicControlButton.allCases).subtracting([.none])
        #expect(Set(MusicControlButton.pickerOptions) == expected)
        #expect(MusicControlButton.pickerOptions.count == expected.count, "No duplicates")
    }

    @Test("iconName is empty only for .none")
    func iconNameEmptyOnlyForNone() {
        for button in MusicControlButton.allCases {
            if button == .none {
                #expect(button.iconName.isEmpty)
            } else {
                #expect(!button.iconName.isEmpty, "\(button) should have a non-empty icon name")
            }
        }
    }

    @Test("prefersLargeScale is true only for playPause")
    func prefersLargeScaleOnlyForPlayPause() {
        for button in MusicControlButton.allCases {
            #expect(button.prefersLargeScale == (button == .playPause))
        }
    }

    @Test("Codable round-trip preserves every case")
    func codableRoundTrip() throws {
        for button in MusicControlButton.allCases {
            let data = try JSONEncoder().encode(button)
            let restored = try JSONDecoder().decode(MusicControlButton.self, from: data)
            #expect(restored == button)
        }
    }
}
