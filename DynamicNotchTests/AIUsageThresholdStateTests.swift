import Testing
import Foundation
@testable import DynamicNotch

// MARK: - Helpers

private let thresholds = [80, 90, 100]

private func date(_ offsetHours: Double) -> Date {
    Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(offsetHours * 3600)
}

/// Feeds readings in order and returns the events from the final one.
@discardableResult
private func feed(
    _ state: inout AIUsageThresholdState,
    _ readings: [(percent: Double, resetsAt: Date?)]
) -> [AIUsageThresholdState.Event] {
    var last: [AIUsageThresholdState.Event] = []
    for reading in readings {
        last = state.ingest(percent: reading.percent, resetsAt: reading.resetsAt, thresholds: thresholds)
    }
    return last
}

// MARK: - Tests

@Suite("AI usage threshold edge triggering")
struct AIUsageThresholdStateTests {

    @Test("The first reading never fires, even when already over a threshold")
    func firstReadingIsSilent() {
        var state = AIUsageThresholdState()
        let events = state.ingest(percent: 0.95, resetsAt: date(1), thresholds: thresholds)
        #expect(events.isEmpty, "Enabling alerts at 95% should not immediately announce 80 and 90")
        #expect(state.lastNotifiedThreshold == 90, "State should be seeded to the highest threshold already passed")
    }

    @Test("Crossing a threshold fires exactly once, not on every later poll")
    func crossingFiresOnce() {
        var state = AIUsageThresholdState()
        feed(&state, [(0.50, date(1))])

        let crossing = state.ingest(percent: 0.82, resetsAt: date(1), thresholds: thresholds)
        #expect(crossing == [.crossed(threshold: 80, percent: 82)])

        // Sitting above the line must stay quiet — a 5 minute poll would otherwise
        // notify twelve times an hour.
        for percent in [0.83, 0.85, 0.88] {
            let repeated = state.ingest(percent: percent, resetsAt: date(1), thresholds: thresholds)
            #expect(repeated.isEmpty, "Still at \(percent) should not re-announce 80%")
        }
    }

    @Test("A jump past several thresholds fires only the highest")
    func jumpFiresHighestOnly() {
        var state = AIUsageThresholdState()
        feed(&state, [(0.20, date(1))])

        let events = state.ingest(percent: 0.97, resetsAt: date(1), thresholds: thresholds)
        #expect(events == [.crossed(threshold: 90, percent: 97)], "20% → 97% is one alert, not 80 and 90")
    }

    @Test("A later reset date rolls the window and re-arms the thresholds")
    func windowRollRearms() {
        var state = AIUsageThresholdState()
        feed(&state, [(0.20, date(1)), (0.85, date(1))])
        #expect(state.lastNotifiedThreshold == 80)

        let rolled = state.ingest(percent: 0.05, resetsAt: date(6), thresholds: thresholds)
        #expect(rolled == [.windowReset(previousPeak: 85)])
        #expect(state.lastNotifiedThreshold == 0, "A new window should re-arm every threshold")

        let refires = state.ingest(percent: 0.81, resetsAt: date(6), thresholds: thresholds)
        #expect(refires == [.crossed(threshold: 80, percent: 81)], "80% should fire again in the new window")
    }

    @Test("Reset is reported with the peak of the window that ended, not the current reading")
    func resetCarriesPreviousPeak() {
        var state = AIUsageThresholdState()
        feed(&state, [(0.20, date(1)), (0.99, date(1)), (0.99, date(1))])

        let rolled = state.ingest(percent: 0.02, resetsAt: date(6), thresholds: thresholds)
        #expect(rolled == [.windowReset(previousPeak: 99)])
    }

    @Test("A usage cliff rolls the window when the provider gives no reset date")
    func windowRollWithoutDate() {
        var state = AIUsageThresholdState()
        feed(&state, [(0.20, nil), (0.92, nil)])

        let rolled = state.ingest(percent: 0.01, resetsAt: nil, thresholds: thresholds)
        #expect(rolled == [.windowReset(previousPeak: 92)])
    }

    @Test("Ordinary fluctuation is not mistaken for a reset")
    func smallDipIsNotAReset() {
        var state = AIUsageThresholdState()
        feed(&state, [(0.60, date(1))])

        let events = state.ingest(percent: 0.55, resetsAt: date(1), thresholds: thresholds)
        #expect(events.isEmpty, "A 5 point dip is noise, not a new window")
    }

    @Test("Disabled threshold slots are ignored")
    func zeroThresholdsIgnored() {
        var state = AIUsageThresholdState()
        _ = state.ingest(percent: 0.10, resetsAt: date(1), thresholds: [0, 90, 0])

        let below = state.ingest(percent: 0.85, resetsAt: date(1), thresholds: [0, 90, 0])
        #expect(below.isEmpty, "85% should not fire when only the 90% slot is enabled")

        let above = state.ingest(percent: 0.91, resetsAt: date(1), thresholds: [0, 90, 0])
        #expect(above == [.crossed(threshold: 90, percent: 91)])
    }

    @Test("Round tripping through Defaults storage preserves the window state")
    func codableRoundTrip() throws {
        var state = AIUsageThresholdState()
        feed(&state, [(0.20, date(1)), (0.85, date(1))])

        let data = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(AIUsageThresholdState.self, from: data)
        #expect(restored == state, "A relaunch must not lose which thresholds were already announced")

        var reloaded = restored
        let events = reloaded.ingest(percent: 0.86, resetsAt: date(1), thresholds: thresholds)
        #expect(events.isEmpty, "Relaunching mid-window should not re-fire an alert the user already saw")
    }
}
