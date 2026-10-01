//
//  CrashReportView.swift
//  DynamicNotch
//
//  Shown either automatically (DynamicNotchApp opens Settings -> About on launch
//  when a new, unacknowledged crash is found) or manually (the "Check for Crash
//  Reports" row in AboutSettings) - both paths land here, so there's exactly one
//  place that knows how to show a crash and act on it.
//
//  Shows the raw crash report and the curated diagnostic log tail *before*
//  anything is written to disk or any app is opened - nothing leaves the device
//  without the user seeing it first.
//

import SwiftUI

struct CrashReportView: View {
    let report: CrashReport
    var onDismiss: () -> Void

    @State private var crashText: String = "Loading…"
    @State private var showPreRedirectInstructions = false
    @State private var isExporting = false

    private var logTail: String {
        let lines = DiagnosticsCollector.currentContents().split(separator: "\n", omittingEmptySubsequences: true)
        let tail = lines.suffix(80).joined(separator: "\n")
        return tail.isEmpty ? "(no recent log entries)" : tail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(report.process) Quit Unexpectedly")
                        .font(.headline)
                    Text(report.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text("Crash Report")
                .font(.subheadline.bold())
            logBox(crashText)

            Text("Recent Diagnostic Log")
                .font(.subheadline.bold())
            logBox(logTail)

            HStack {
                Spacer()
                Button("Not Now") {
                    CrashReportScanner.acknowledge(report)
                    onDismiss()
                }
                Button("Report on GitHub") {
                    CrashReportScanner.acknowledge(report)
                    showPreRedirectInstructions = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.effectiveAccent)
                .disabled(isExporting)
            }
        }
        .padding(24)
        .frame(width: 520)
        .task {
            crashText = (try? String(contentsOf: report.url, encoding: .utf8)) ?? "Could not read crash report at \(report.url.lastPathComponent)."
        }
        .alert("Finder and Your Browser Will Open", isPresented: $showPreRedirectInstructions) {
            Button("Continue") {
                isExporting = true
                Task {
                    await BugReportExporter.export(crashReport: (report, crashText))
                    isExporting = false
                    onDismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Finder will open with your crash report, diagnostic log, and full log selected, and your browser will open to the bug report page. Drag all three into the \u{201C}Attach Files & Screenshots\u{201D} field there.")
        }
    }

    private func logBox(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(height: 120)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
