//
//  ThermalView.swift
//  boringNotch
//

import SwiftUI
import Defaults

// MARK: - Open-notch thermal tab

struct ThermalView: View {
    @ObservedObject private var thermal = ThermalManager.shared

    var body: some View {
        Group {
            if !thermal.isAvailable {
                unavailableView
            } else {
                readoutView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unavailableView: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Thermal sensors unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var peakTemp: Float {
        max(thermal.cpuTemp, thermal.gpuTemp)
    }

    private var readoutView: some View {
        HStack(spacing: 0) {
            tempGauge
            if !thermal.fanRPMs.isEmpty {
                separator
                fanColumn
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var tempGauge: some View {
        VStack(spacing: 4) {
            Text("\(Int(peakTemp))°")
                .font(.system(size: 48, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(tempColor(peakTemp))
                .contentTransition(.numericText())
                .animation(.smooth, value: peakTemp)
            Text("Peak temp")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 100)
    }

    private var fanColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(thermal.fanRPMs.enumerated()), id: \.offset) { i, rpm in
                HStack(spacing: 6) {
                    Image(systemName: "fan.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(Int(rpm)) RPM")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.smooth, value: rpm)
                }
            }
        }
        .frame(minWidth: 90)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 44)
            .padding(.horizontal, 20)
    }

    private func tempColor(_ temp: Float) -> Color {
        switch temp {
        case ..<60:  return .white
        case ..<75:  return Color(red: 1.0, green: 0.85, blue: 0.3)
        case ..<90:  return .orange
        default:     return .red
        }
    }
}

// MARK: - Closed-notch thermal alert strip

struct ThermalClosedAlert: View {
    @EnvironmentObject var vm: BoringViewModel
    let temp: Float

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "thermometer.high")
                    .imageScale(.small)
                    .foregroundStyle(.orange)
                Text("High temp")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.85))
            }

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - 20)

            Text("\(Int(temp))°C")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.orange)
        }
    }
}
