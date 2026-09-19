//
//  AIUsageThresholdState.swift
//  boringNotch
//
//  Edge-trigger bookkeeping for AI usage alerts.
//
//  Kept as a plain value type with no dependencies so it can be exercised
//  directly in tests: feed it a sequence of readings, assert on the events.
//

import Defaults
import Foundation

struct AIUsageThresholdState: Codable, Defaults.Serializable, Equatable {
    /// Highest threshold already announced for the current window. 0 = none yet.
    var lastNotifiedThreshold: Int = 0
    /// Reset date of the window these numbers describe.
    var windowEnd: Date?
    /// Highest usage seen during the current window, 0–100.
    var peakPercent: Double = 0
    /// Most recent reading, 0–100. Used to spot a reset when the provider gives no date.
    var lastPercent: Double = 0
    /// False until the first reading lands.
    var hasSample: Bool = false

    enum Event: Equatable {
        case crossed(threshold: Int, percent: Double)
        case windowReset(previousPeak: Double)
    }

    /// Folds in a new reading and reports what the user should be told about.
    ///
    /// - Parameters:
    ///   - percent: Usage as a fraction, 0…1.
    ///   - resetsAt: End of the current window, when the provider reports one.
    ///   - thresholds: Percentages worth announcing. Values outside 1...100 are ignored.
    /// - Returns: Events to act on, in the order they happened.
    mutating func ingest(percent: Double, resetsAt: Date?, thresholds: [Int]) -> [Event] {
        let pct = min(max(percent, 0), 1) * 100
        let wanted = thresholds.filter { (1 ... 100).contains($0) }
        var events: [Event] = []

        // A window rolls when the provider hands us a later reset date. Providers
        // that omit the date still show a cliff in usage, so treat that as a roll too.
        var rolledByDate = false
        if let end = windowEnd, let next = resetsAt {
            rolledByDate = next > end
        }
        let rolledByDrop = hasSample && (lastPercent - pct) >= 50

        if hasSample, rolledByDate || rolledByDrop {
            events.append(.windowReset(previousPeak: peakPercent))
            lastNotifiedThreshold = 0
            peakPercent = 0
        }

        let isFirstEverReading = !hasSample
        hasSample = true
        windowEnd = resetsAt
        lastPercent = pct
        peakPercent = max(peakPercent, pct)

        // Seed rather than announce on the very first reading. Turning alerts on
        // while already at 95% should not immediately fire every threshold below it.
        if isFirstEverReading {
            lastNotifiedThreshold = wanted.filter { pct >= Double($0) }.max() ?? 0
            return events
        }

        // Only the highest newly-crossed threshold fires — jumping 70% → 95% is one
        // alert, not one per threshold passed.
        if let crossed = wanted.filter({ pct >= Double($0) && $0 > lastNotifiedThreshold }).max() {
            lastNotifiedThreshold = crossed
            events.append(.crossed(threshold: crossed, percent: pct))
        }

        return events
    }
}
