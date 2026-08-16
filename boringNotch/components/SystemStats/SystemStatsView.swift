//
//  SystemStatsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct SystemStatsView: View {
    @ObservedObject private var stats = SystemStatsManager.shared
    @Default(.showStatsCPU)  private var showCPU
    @Default(.showStatsRAM)  private var showRAM
    @Default(.showStatsSwap) private var showSwapSetting

    private var showSwap: Bool { showSwapSetting && stats.swapTotalGB > 0 }

    var body: some View {
        HStack(spacing: 0) {
            if showCPU {
                cpuSection
            }
            if showRAM {
                if showCPU { separator }
                ramSection
            }
            if showSwap {
                if showCPU || showRAM { separator }
                swapSection
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sections

    private var cpuSection: some View {
        VStack(spacing: 4) {
            Text("\(Int(stats.cpuPercent.rounded()))%")
                .font(.system(size: 40, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(cpuColor)
                .contentTransition(.numericText())
                .animation(.smooth, value: stats.cpuPercent)
            Text("CPU")
                .font(.caption)
                .foregroundStyle(.secondary)
            StatBar(fraction: stats.cpuPercent / 100, color: cpuColor)
                .frame(width: 70, height: 4)
        }
        .frame(minWidth: 100)
    }

    private var ramSection: some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(String(format: "%.1f", stats.ramUsedGB))
                    .font(.system(size: 40, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.smooth, value: stats.ramUsedGB)
                Text("/ \(Int(stats.ramTotalGB)) GB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("RAM")
                .font(.caption)
                .foregroundStyle(.secondary)
            StatBar(fraction: stats.ramTotalGB > 0 ? stats.ramUsedGB / stats.ramTotalGB : 0, color: .white)
                .frame(width: 70, height: 4)
        }
        .frame(minWidth: 130)
    }

    private var swapSection: some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(String(format: "%.1f", stats.swapUsedGB))
                    .font(.system(size: 40, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(stats.swapUsedGB > 0.01 ? Color.orange : Color.white)
                    .contentTransition(.numericText())
                    .animation(.smooth, value: stats.swapUsedGB)
                Text("GB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Swap")
                .font(.caption)
                .foregroundStyle(.secondary)
            StatBar(
                fraction: stats.swapTotalGB > 0 ? stats.swapUsedGB / stats.swapTotalGB : 0,
                color: stats.swapUsedGB > 0.01 ? .orange : .white
            )
            .frame(width: 70, height: 4)
        }
        .frame(minWidth: 100)
    }

    // MARK: - Helpers

    private var separator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 44)
            .padding(.horizontal, 20)
    }

    private var cpuColor: Color {
        switch stats.cpuPercent {
        case ..<50:  return .white
        case ..<75:  return Color(red: 1.0, green: 0.85, blue: 0.3)
        case ..<90:  return .orange
        default:     return .red
        }
    }
}

private struct StatBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.15))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
                    .animation(.smooth, value: fraction)
            }
        }
    }
}
