//
//  ThermalView.swift
//  boringNotch
//

import SwiftUI
import Defaults

// MARK: - Open-notch thermal tab

struct ThermalView: View {
    @ObservedObject private var thermal = ThermalManager.shared
    @Default(.fanCurvePreset) private var activePreset
    @Default(.thermalNotchPresets) private var notchPresets

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
            separator
            if thermal.hasFans {
                fanColumn
                separator
                presetList
            } else {
                fanlessLabel
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

    private var fanlessLabel: some View {
        VStack(spacing: 4) {
            Image(systemName: "wind")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Fanless")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var visiblePresets: [FanCurvePreset] {
        FanCurvePreset.allCases.filter { notchPresets.contains($0) }
    }

    private var chipFontSize: CGFloat {
        switch visiblePresets.count {
        case 1:  return 13
        case 2:  return 11
        default: return 9
        }
    }

    private var chipPaddingH: CGFloat { visiblePresets.count == 1 ? 11 : visiblePresets.count == 2 ? 9 : 7 }
    private var chipPaddingV: CGFloat { visiblePresets.count == 1 ? 6  : visiblePresets.count == 2 ? 4 : 3 }
    private var chipSpacing: CGFloat  { visiblePresets.count == 1 ? 0  : visiblePresets.count == 2 ? 6 : 3 }

    private var presetList: some View {
        VStack(alignment: .leading, spacing: chipSpacing) {
            ForEach(visiblePresets) { preset in
                presetChip(preset)
            }
        }
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func presetChip(_ preset: FanCurvePreset) -> some View {
        let isActive = activePreset == preset
        Button {
            applyPreset(preset)
        } label: {
            Text(preset.shortName)
                .font(.system(size: chipFontSize, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.black : Color.white.opacity(0.65))
                .padding(.horizontal, chipPaddingH)
                .padding(.vertical, chipPaddingV)
                .background(
                    Capsule()
                        .fill(isActive ? Color.white : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    private func applyPreset(_ preset: FanCurvePreset) {
        Defaults[.fanCurvePreset] = preset
        switch preset {
        case .appleDefault:
            Defaults[.fanCurveEnabled] = false
        case .maxSpeed:
            Defaults[.fanCurveEnabled] = false
        case .custom:
            Defaults[.fanCurveEnabled] = true
        default:
            if let pts = preset.curvePoints {
                Defaults[.fanCurvePoints] = pts
            }
            Defaults[.fanCurveEnabled] = true
        }
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
