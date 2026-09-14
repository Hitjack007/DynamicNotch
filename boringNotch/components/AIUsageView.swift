//
//  AIUsageView.swift
//  boringNotch
//
//  Open-notch tab view for AI usage (Claude or ChatGPT).
//

import Defaults
import SwiftUI

struct AIUsageView: View {
    @Default(.aiUsageProvider) var aiUsageProvider
    @ObservedObject private var claudeManager = ClaudeUsageManager.shared
    @ObservedObject private var chatgptManager = ChatGPTUsageManager.shared

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
                .animation(.smooth, value: usagePercent)
            Text(aiUsageProvider == .claude ? "Claude" : "ChatGPT")
                .font(.caption)
                .foregroundStyle(.secondary)
            StatBar(fraction: usagePercent, color: usageColor)
                .frame(width: 70, height: 4)
        }
        .frame(minWidth: 100)
    }

    // MARK: - Info section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !limitKind.isEmpty {
                statLine(value: limitKind, label: "limit")
            }

            if windowResetsAt != nil {
                TimelineView(.periodic(from: Date(), by: 30)) { _ in
                    statLine(value: timeUntilReset, label: "until reset")
                }
            }

            authActionView
        }
        .frame(minWidth: 150, alignment: .leading)
        .padding(.leading, 20)
    }

    @ViewBuilder
    private var authActionView: some View {
        if aiUsageProvider == .claude {
            switch claudeManager.authState {
            case .expired:
                Button("Re-authenticate") { Task { await claudeManager.reauthenticate() } }
                    .buttonStyle(.borderedProminent).controlSize(.small).tint(.effectiveAccent)
            case .error(let msg):
                Text(msg).font(.caption2).foregroundStyle(.red).lineLimit(2)
            case .unauthenticated:
                Text("Not authenticated").font(.caption2).foregroundStyle(.secondary)
            default:
                EmptyView()
            }
        } else {
            switch chatgptManager.authState {
            case .expired:
                Button("Re-authenticate") { Task { await chatgptManager.reauthenticate() } }
                    .buttonStyle(.borderedProminent).controlSize(.small).tint(.effectiveAccent)
            case .error(let msg):
                Text(msg).font(.caption2).foregroundStyle(.red).lineLimit(2)
            case .unauthenticated:
                Text("Not authenticated").font(.caption2).foregroundStyle(.secondary)
            default:
                EmptyView()
            }
        }
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

    private var usagePercent: Double {
        aiUsageProvider == .claude ? claudeManager.usagePercent : chatgptManager.usagePercent
    }

    private var limitKind: String {
        aiUsageProvider == .claude ? claudeManager.limitKind : chatgptManager.limitKind
    }

    private var timeUntilReset: String {
        aiUsageProvider == .claude ? claudeManager.timeUntilReset : chatgptManager.timeUntilReset
    }

    private var windowResetsAt: Date? {
        aiUsageProvider == .claude ? claudeManager.windowResetsAt : chatgptManager.windowResetsAt
    }

    private var percentText: String {
        let authenticated = aiUsageProvider == .claude ? claudeManager.isAuthenticated : chatgptManager.isAuthenticated
        guard usagePercent > 0 || authenticated else { return "--" }
        return "\(Int((usagePercent * 100).rounded()))%"
    }

    private var usageColor: Color {
        let pct = usagePercent * 100
        switch pct {
        case ..<50:  return .white
        case ..<75:  return Color(red: 1.0, green: 0.85, blue: 0.3)
        case ..<90:  return .orange
        default:     return .red
        }
    }
}
