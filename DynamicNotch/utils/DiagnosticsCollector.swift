//
//  DiagnosticsCollector.swift
//  DynamicNotch
//
//  Two self-maintained log files, both under ~/Library/Logs/DynamicNotch:
//
//  - dynamicnotch.log ("curated") - errors/faults from any category, plus .notice
//    milestones from launch/updates/extensions specifically. Small (capped, see
//    below), meant to be pasted straight into a bug report.
//  - dynamicnotch-full.log ("full") - every AppLogger call, every level, every
//    category, unconditionally. Meant to be opened directly and traced through
//    when the curated file isn't enough - timestamps on both line up exactly, so
//    there's no ambiguity correlating one against the other.
//
//  Rotation on both is a trailing cap, never a reset on launch: if the app
//  crashes and relaunches, whatever led up to the crash is still in the file
//  when it comes back up, instead of being wiped by a per-launch truncation
//  right when it's needed most.
//
//  Reused by the crash-report flow (CrashReportScanner/CrashReportView) to bundle
//  the curated trail alongside the raw system crash report.
//

import Foundation
import os

enum DiagnosticsCollector {
    /// .notice calls from these categories are small enough in volume to be worth
    /// having in the curated file without digging into the full one - everything
    /// else at .notice level is full-log-only.
    private static let curatedNoticeCategories: Set<String> = ["launch", "updates", "extensions"]

    private static let curated = LogFile(
        filename: "dynamicnotch.log", maxLines: 500, maxBytes: 250 * 1024
    )
    private static let full = LogFile(
        filename: "dynamicnotch-full.log", maxLines: 20_000, maxBytes: 10 * 1024 * 1024
    )

    static var fileURL: URL { curated.url }
    static var fullFileURL: URL { full.url }

    static func record(level: OSLogType, category: String, message: String) {
        let tag: String
        switch level {
        case .debug: tag = "DEBUG"
        case .info: tag = "INFO"
        case .error: tag = "ERROR"
        case .fault: tag = "FAULT"
        default: tag = "NOTICE"
        }
        let line = "[\(isoTimestamp())] [\(tag)] [\(category)] \(message)\n"

        full.append(line)

        // .default is what Logger.notice(_:) maps to under the hood - there's no
        // distinct OSLogType.notice case.
        let qualifiesForCurated = level == .error || level == .fault
            || (level == .default && curatedNoticeCategories.contains(category))
        if qualifiesForCurated {
            curated.append(line)
        }
    }

    /// Current curated log contents, for the Settings "Copy Diagnostics" button and the
    /// crash-report flow. The file is capped small, so a synchronous read is cheap
    /// enough to call from the main actor.
    static func currentContents() -> String {
        curated.currentContents()
    }

    /// Current full log contents, for the "Reveal in Finder" button and the bug-report
    /// export flow. Can be large (up to the full ~10MB cap), so prefer reading it off
    /// the main thread when possible.
    static func currentFullContents() -> String {
        full.currentContents()
    }

    private static func isoTimestamp() -> String { formatter.string(from: Date()) }
    private static let formatter = ISO8601DateFormatter()
}

/// One capped, trailing-rotated log file. Both dynamicnotch.log and
/// dynamicnotch-full.log are just two instances of this with different caps.
private final class LogFile {
    let url: URL
    private let maxLines: Int
    private let maxBytes: Int
    private let trimCheckInterval = 50
    private let queue: DispatchQueue
    private var writesSinceTrim = 0

    init(filename: String, maxLines: Int, maxBytes: Int) {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/DynamicNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent(filename)
        self.maxLines = maxLines
        self.maxBytes = maxBytes
        self.queue = DispatchQueue(label: "com.mark.dynamicnotch.diagnostics.\(filename)", qos: .utility)
    }

    func append(_ line: String) {
        queue.async { [self] in
            guard let data = line.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try? data.write(to: url)
            }

            writesSinceTrim += 1
            if writesSinceTrim >= trimCheckInterval {
                writesSinceTrim = 0
                trimIfNeeded()
            }
        }
    }

    func currentContents() -> String {
        queue.sync {
            (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
    }

    private func trimIfNeeded() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int, size > maxBytes,
              let content = try? String(contentsOf: url, encoding: .utf8) else { return }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > maxLines else { return }
        let trimmed = lines.suffix(maxLines).joined(separator: "\n") + "\n"
        try? trimmed.write(to: url, atomically: true, encoding: .utf8)
    }
}
