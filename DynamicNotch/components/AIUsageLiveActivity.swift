//
//  AIUsageLiveActivity.swift
//  DynamicNotch
//
//  Compact closed-notch live activity for AI usage (Claude or ChatGPT).
//  Layout: [ring OR %] [black notch center] [time remaining]
//

import Defaults
import SwiftUI

struct AIUsageLiveActivity: View {
    @EnvironmentObject var vm: NotchViewModel
    @ObservedObject private var claudeManager = ClaudeUsageManager.shared
    @ObservedObject private var chatgptManager = ChatGPTUsageManager.shared
    @ObservedObject private var batteryModel = BatteryStatusViewModel.shared
    @Default(.aiUsageProvider) var aiUsageProvider
    @Default(.aiUsageClosedNotchShowRing) var showRing

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

    private var usagePercent: Double {
        aiUsageProvider == .claude ? claudeManager.usagePercent : chatgptManager.usagePercent
    }

    private var compactTimeUntilReset: String {
        aiUsageProvider == .claude ? claudeManager.compactTimeUntilReset : chatgptManager.compactTimeUntilReset
    }

    private var hasError: Bool {
        aiUsageProvider == .claude ? claudeManager.hasError : chatgptManager.hasError
    }

    // MARK: - Left: ring, %, or error

    @ViewBuilder
    private var leftIndicator: some View {
        if hasError {
            // An empty ring reads as "nothing used", which is exactly the wrong
            // thing to show when the reading failed.
            Image(systemName: "exclamationmark.octagon")
                .font(.system(size: indicatorSize * 0.75))
                .foregroundStyle(.secondary)
                .frame(width: indicatorSize, height: indicatorSize)
        } else if showRing {
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
                .trim(from: 0, to: usagePercent)
                .stroke(usageColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: usagePercent)
        }
        .frame(width: indicatorSize, height: indicatorSize)
    }

    private var percentLabel: some View {
        Text("\(Int((usagePercent * 100).rounded()))%")
            .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(usageColor)
            .frame(width: indicatorSize)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .animation(.smooth, value: usagePercent)
    }

    // MARK: - Right: time remaining, or charging glyph

    /// See `ContentView.showsChargingGlyph` for why this keys off `isCharging`
    /// rather than `isPluggedIn`.
    private var showsChargingGlyph: Bool {
        #if DEBUG
        if batteryModel.debugForceCharging { return true }
        #endif
        return batteryModel.isCharging && Defaults[.showPowerStatusNotifications]
    }

    @ViewBuilder
    private var rightIndicator: some View {
        if showsChargingGlyph {
            ChargingSlotGlyph(size: indicatorSize)
        } else {
            TimelineView(.periodic(from: Date(), by: 60)) { _ in
                Text(hasError ? "--" : compactTimeUntilReset)
                    .font(.system(size: 9, weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: indicatorSize)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    // MARK: - Helpers

    private var usageColor: Color {
        switch usagePercent * 100 {
        case ..<75: return .white
        case ..<90: return .orange
        default:    return .red
        }
    }
}
