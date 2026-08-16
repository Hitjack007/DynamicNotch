//
//  ClaudeUsageLiveActivity.swift
//  boringNotch
//
//  Compact closed-notch live activity for Claude usage.
//  Layout: [ring OR %] [black notch center] [time remaining]
//

import Defaults
import SwiftUI

struct ClaudeUsageLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var manager = ClaudeUsageManager.shared
    @Default(.claudeClosedNotchShowRing) var showRing

    var body: some View {
        HStack(spacing: 0) {
            leftIndicator
                .padding(.trailing, 4)
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)
            rightIndicator
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    private var indicatorSize: CGFloat { max(0, vm.effectiveClosedNotchHeight - 12) }

    // MARK: - Left: ring or %

    @ViewBuilder
    private var leftIndicator: some View {
        if showRing {
            progressRing
        } else {
            percentLabel
        }
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 2)
            Circle()
                .trim(from: 0, to: manager.usagePercent)
                .stroke(usageColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: manager.usagePercent)
        }
        .frame(width: indicatorSize, height: indicatorSize)
    }

    private var percentLabel: some View {
        Text("\(Int((manager.usagePercent * 100).rounded()))%")
            .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(usageColor)
            .frame(width: indicatorSize)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .animation(.smooth, value: manager.usagePercent)
    }

    // MARK: - Right: time remaining

    private var rightIndicator: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { _ in
            Text(manager.compactTimeUntilReset)
                .font(.system(size: 9, weight: .regular, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: indicatorSize)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    // MARK: - Helpers

    private var usageColor: Color {
        switch manager.usagePercent * 100 {
        case ..<75: return .white
        case ..<90: return .orange
        default:    return .red
        }
    }
}
