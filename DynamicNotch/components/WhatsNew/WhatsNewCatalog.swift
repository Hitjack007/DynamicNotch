//
//  WhatsNewCatalog.swift
//  DynamicNotch
//
//  Created by Mark Greene on 2026-09-20.
//

import Foundation

struct WhatsNewHighlight: Identifiable {
    let id: String              // stable slug, e.g. "extensions"
    let icon: String            // SF Symbol
    let title: LocalizedStringResource
    let body: LocalizedStringResource
    var action: WhatsNewAction? = nil
}

enum WhatsNewAction {
    case settings(tab: String, label: LocalizedStringResource)   // tab = SettingsView's selectedTab string
    case link(URL, label: LocalizedStringResource)
    case permission(PermissionRequester.Kind, label: LocalizedStringResource)
    /// Renders the unskippable thermal daemon migration flow instead of a normal button.
    /// Not tied to a specific release - synthesized at launch by DynamicNotchApp whenever
    /// ThermalDaemonClient.migrationNeeded is true, so it isn't part of `releases` below.
    case thermalDaemonMigrate
}

struct WhatsNewRelease {
    let version: String
    let highlights: [WhatsNewHighlight]
}

struct WhatsNewPage: Identifiable {
    let version: String
    let highlight: WhatsNewHighlight
    var id: String { "\(version)-\(highlight.id)" }
}

enum WhatsNewCatalog {
    /// Newest last.
    static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(
            version: "27.3",
            highlights: [
                WhatsNewHighlight(
                    id: "extensions",
                    icon: "bolt.badge.a",
                    title: "Automate with Extensions",
                    body: "Describe a small automation — like turning Caffeine on when Xcode is frontmost — and DynamicNotch will run it every time, no code required.",
                    action: .settings(tab: "Extensions", label: "Open Extensions")
                ),
                WhatsNewHighlight(
                    id: "reorderableActivities",
                    icon: "arrow.up.arrow.down",
                    title: "Reorder Notch Activities",
                    body: "Drag your notch activities into the order you actually want them, right from General settings.",
                    action: .settings(tab: "General", label: "Open General")
                ),
                WhatsNewHighlight(
                    id: "aiUsagePromotion",
                    icon: "apple.intelligence",
                    title: "AI Usage, Front and Center",
                    body: "When you're getting close to your Claude or ChatGPT usage limit, DynamicNotch now promotes the alert so it's harder to miss.",
                    action: .settings(tab: "AIUsage", label: "Open AI Usage")
                ),
            ]
        ),
    ]

    /// Compares two version strings numerically, so "27.9" < "27.10" and "27.2" < "27.2.1".
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedDescending
    }

    /// Pages to show on first launch after an update, in ascending version order.
    ///
    /// An empty `lastSeenVersion` means an existing user is upgrading into this feature with no
    /// key written yet — only the release matching `currentVersion` is shown, not the backlog of
    /// historical entries.
    static func pages(
        lastSeenVersion: String,
        currentVersion: String,
        releases: [WhatsNewRelease] = WhatsNewCatalog.releases
    ) -> [WhatsNewPage] {
        let eligibleReleases: [WhatsNewRelease]
        if lastSeenVersion.isEmpty {
            eligibleReleases = releases.filter { $0.version == currentVersion }
        } else {
            eligibleReleases = releases.filter {
                isVersion($0.version, newerThan: lastSeenVersion)
                    && !isVersion($0.version, newerThan: currentVersion)
            }
        }

        let ordered = eligibleReleases.sorted { isVersion($1.version, newerThan: $0.version) }
        return ordered.flatMap { release in
            release.highlights.map { WhatsNewPage(version: release.version, highlight: $0) }
        }
    }

    /// Synthesized migration gate shown whenever ThermalDaemonClient.migrationNeeded is true,
    /// regardless of app version or the "show what's new" preference. Not part of `releases`.
    static let thermalDaemonMigrationHighlight = WhatsNewHighlight(
        id: "thermalDaemonMigration-v\(ThermalDaemonClient.currentProtocolVersion)",
        icon: "fan.fill",
        title: "Fan Control Needs an Update",
        body: "The fan control daemon has been rebuilt with smoother speed ramping and a more reliable installer. Run the update below to keep using custom fan curves.",
        action: .thermalDaemonMigrate
    )

    /// Looks up a highlight by its stable slug, so onboarding can reuse the exact same
    /// content as the What's New flow instead of duplicating it.
    static func highlight(id: String) -> WhatsNewHighlight {
        guard let highlight = releases.flatMap(\.highlights).first(where: { $0.id == id }) else {
            fatalError("Missing WhatsNewHighlight for id \"\(id)\" — check WhatsNewCatalog.releases")
        }
        return highlight
    }
}
