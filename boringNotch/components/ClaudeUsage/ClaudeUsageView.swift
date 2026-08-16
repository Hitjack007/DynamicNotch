//
//  ClaudeUsageView.swift
//  boringNotch
//
//  Open-notch tab view for Claude usage — mirrors the SystemStatsView layout.
//

import Defaults
import SwiftUI

struct ClaudeUsageView: View {
    @ObservedObject private var manager = ClaudeUsageManager.shared

    var body: some View {
        HStack(spacing: 0) {
            usageSection
            separator
            infoSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Usage section (large %)

    private var usageSection: some View {
        VStack(spacing: 4) {
            Text(percentText)
                .font(.system(size: 40, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(usageColor)
                .contentTransition(.numericText())
                .animation(.smooth, value: manager.usagePercent)
            Text("Claude")
                .font(.caption)
                .foregroundStyle(.secondary)
            StatBar(fraction: manager.usagePercent, color: usageColor)
                .frame(width: 70, height: 4)
        }
        .frame(minWidth: 100)
    }

    // MARK: - Info section (tokens + reset)

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !manager.limitKind.isEmpty {
                statLine(value: manager.limitKind, label: "limit")
            }

            if manager.windowResetsAt != nil {
                TimelineView(.periodic(from: Date(), by: 30)) { _ in
                    statLine(value: manager.timeUntilReset, label: "until reset")
                }
            }

            switch manager.authState {
            case .expired:
                Button("Re-authenticate") {
                    Task { await manager.reauthenticate() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.effectiveAccent)

            case .error(let msg):
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)

            case .unauthenticated:
                Text("Not authenticated")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

            default:
                EmptyView()
            }
        }
        .frame(minWidth: 150, alignment: .leading)
        .padding(.leading, 20)
    }

    // MARK: - Separator

    private var separator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 44)
            .padding(.horizontal, 20)
    }

    // MARK: - Helpers

    private func statLine(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.subheadline, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var percentText: String {
        guard manager.usagePercent > 0 || manager.authState == .authenticated else { return "--" }
        return "\(Int((manager.usagePercent * 100).rounded()))%"
    }

    private var usageColor: Color {
        let pct = manager.usagePercent * 100
        switch pct {
        case ..<50:  return .white
        case ..<75:  return Color(red: 1.0, green: 0.85, blue: 0.3)
        case ..<90:  return .orange
        default:     return .red
        }
    }
}
