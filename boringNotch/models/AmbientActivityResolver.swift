//
//  AmbientActivityResolver.swift
//  boringNotch
//
//  Decides which of Music/Download/Face/AI Usage wins the closed-notch ambient
//  slot, given a user-configured priority order and which activities are
//  currently active.
//
//  Kept as a plain value type with no dependencies so it can be exercised
//  directly in tests: feed it an order and an availability snapshot, assert
//  on the winner.
//

import Foundation

struct AmbientActivityResolver {
    /// Whether each ambient activity is currently eligible to be shown, plus
    /// the one piece of state (AI usage promotion) that can override position
    /// in the order rather than just eligibility.
    struct Availability {
        var musicPlaying: Bool
        var musicEnabled: Bool
        var hasActiveDownloads: Bool
        var downloadEnabled: Bool
        var faceEnabled: Bool
        var aiUsageAvailable: Bool
        var aiUsagePromoted: Bool

        func isActive(_ activity: AmbientActivity) -> Bool {
            switch activity {
            case .music:    return musicPlaying && musicEnabled
            case .download: return hasActiveDownloads && downloadEnabled
            case .face:     return faceEnabled
            case .aiUsage:  return aiUsageAvailable
            }
        }
    }

    /// Repairs a stored order against the current set of cases: drops entries
    /// that no longer exist (e.g. from a downgrade or corrupted defaults), and
    /// appends any case missing from the stored order (e.g. a new activity
    /// added in a later release) so it is never silently unreachable.
    static func normalize(_ order: [AmbientActivity]) -> [AmbientActivity] {
        var seen = Set<AmbientActivity>()
        var result: [AmbientActivity] = []
        for activity in order where seen.insert(activity).inserted {
            result.append(activity)
        }
        for activity in AmbientActivity.allCases where !seen.contains(activity) {
            result.append(activity)
        }
        return result
    }

    /// The activity that should occupy the ambient slot, or `nil` if none are
    /// active. AI usage promotion takes priority over the stored order — while
    /// promoted, AI usage is treated as first regardless of where the user
    /// ranked it — but never overrides `aiUsageAvailable == false`.
    static func resolve(order: [AmbientActivity], availability: Availability) -> AmbientActivity? {
        var effectiveOrder = normalize(order)
        if availability.aiUsagePromoted {
            effectiveOrder.removeAll { $0 == .aiUsage }
            effectiveOrder.insert(.aiUsage, at: 0)
        }
        return effectiveOrder.first { availability.isActive($0) }
    }
}
