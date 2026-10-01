//
//  BugReportExporter.swift
//  DynamicNotch
//
//  Turns the diagnostic logs (plus a crash report, when there is one) into a GitHub
//  bug report with as little friction as possible: writes them as named files, opens
//  the browser to the existing bug-report issue form, then reveals the files in
//  Finder so they can be dragged in directly - GitHub's issue textarea accepts
//  dropped files as real attachments, no URL-length limit to worry about, unlike
//  trying to prefill the whole log into the URL itself. No clipboard copy - dragging
//  is the primary (only) path in, since prefilled URL fields turned out to be
//  non-editable once GitHub renders the form.
//

import AppKit
import Defaults
import Foundation

enum BugReportExporter {
    private static let cleanupInterval: TimeInterval = 7 * 24 * 60 * 60  // 1 week
    private static let repoIssuesURL = "https://github.com/Hitjack007/DynamicNotch/issues/new"

    private static var bugReportsDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DynamicNotch/BugReports", isDirectory: true)
    }

    /// The crash-report flow (a real or simulated crash was found) and the general
    /// "Report an Issue" button both land here - the only difference is whether a
    /// CrashReport.txt gets written alongside the two log files.
    static func export(crashReport: (report: CrashReport, crashText: String)? = nil) async {
        let folderName = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let exportDir = bugReportsDir.appendingPathComponent(folderName, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        } catch {
            AppLogger.general.error("BugReportExporter: failed to create export directory, \(type(of: error))")
            return
        }

        let logFileURL = exportDir.appendingPathComponent("DiagnosticLog.txt")
        let fullLogFileURL = exportDir.appendingPathComponent("FullLog.txt")
        var filesToReveal = [logFileURL, fullLogFileURL]

        do {
            try DiagnosticsCollector.currentContents().write(to: logFileURL, atomically: true, encoding: .utf8)
            try DiagnosticsCollector.currentFullContents().write(to: fullLogFileURL, atomically: true, encoding: .utf8)

            if let crashReport {
                let crashFileURL = exportDir.appendingPathComponent("CrashReport.txt")
                try crashReport.crashText.write(to: crashFileURL, atomically: true, encoding: .utf8)
                filesToReveal.insert(crashFileURL, at: 0)
            }
        } catch {
            AppLogger.general.error("BugReportExporter: failed to write export files, \(type(of: error))")
            return
        }

        guard let issueURL = URL(string: "\(repoIssuesURL)?template=1-bug-report-form.yml") else { return }

        // Order matters: open the browser first, then reveal Finder. macOS brings
        // whichever app was activated *last* to the front, so Finder activating second
        // means it ends up on top of the browser, on the same Space, with both visible
        // for the actual drag - the other order would leave the browser covering Finder.
        await openAndWait(issueURL)

        // The open's completion firing isn't actually proof the browser's window has
        // finished being raised - in practice Safari in particular can still be mid
        // animation/activation after the completion handler already fired, so Finder's
        // activation right after can still end up winning and landing on top anyway.
        // This fixed delay is a blunt instrument (no real signal to wait on instead),
        // but it's what closes the gap in practice.
        try? await Task.sleep(for: .milliseconds(800))

        NSWorkspace.shared.activateFileViewerSelecting(filesToReveal)
        if let crashReport {
            AppLogger.general.notice("BugReportExporter: exported crash report \(crashReport.report.id) and opened GitHub issue")
        } else {
            AppLogger.general.notice("BugReportExporter: exported logs and opened GitHub issue")
        }
    }

    private static func openAndWait(_ url: URL) async {
        await withCheckedContinuation { continuation in
            NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { app, error in
                if let error {
                    AppLogger.general.error("BugReportExporter: failed to open GitHub issue URL, \(type(of: error))")
                }
                continuation.resume()
            }
        }
    }

    /// Checked on every launch; only actually sweeps once a week. Collapses the export
    /// folder down to just the single most-recently-created bundle - this is scoped to
    /// these exported snapshots only, not DiagnosticsCollector's curated log, which is a
    /// separate, continuously-rotating file with its own trailing-size cap.
    static func cleanupOldExportsIfDue() {
        if let lastCleanup = Defaults[.lastBugReportCleanupDate],
           Date().timeIntervalSince(lastCleanup) < cleanupInterval {
            return
        }
        defer { Defaults[.lastBugReportCleanupDate] = Date() }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: bugReportsDir, includingPropertiesForKeys: [.contentModificationDateKey]
        ), contents.count > 1 else { return }

        let sortedNewestFirst = contents.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return lhsDate > rhsDate
        }

        for stale in sortedNewestFirst.dropFirst() {
            try? FileManager.default.removeItem(at: stale)
        }
        AppLogger.general.notice("BugReportExporter: weekly cleanup removed \(sortedNewestFirst.count - 1) old export bundle(s)")
    }
}
