import SwiftUI
import Defaults

struct IdleNotchView: View {
    @EnvironmentObject var vm: BoringViewModel
    @Default(.idleNotchLeftWidget) var leftWidget
    @Default(.idleNotchRightWidget) var rightWidget

    var indicatorSize: CGFloat { max(0, vm.effectiveClosedNotchHeight - 12) }

    var body: some View {
        HStack(spacing: 0) {
            widgetView(for: leftWidget)
                .padding(.trailing, 4)
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)
            widgetView(for: rightWidget)
                .padding(.leading, 4)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    @ViewBuilder
    func widgetView(for widget: IdleNotchWidget) -> some View {
        switch widget {
        case .none:
            Color.clear.frame(width: indicatorSize)
        case .batteryMac:
            BatteryIdleWidget(size: indicatorSize)
        case .bluetooth:
            BluetoothIdleWidget(size: indicatorSize)
        case .nextEvent:
            NextEventIdleWidget(size: indicatorSize)
        case .temperature:
            TemperatureIdleWidget(size: indicatorSize)
        case .claudeUsage:
            ClaudeUsageIdleWidget(size: indicatorSize)
        case .time:
            TimeIdleWidget(size: indicatorSize)
        }
    }
}

// MARK: - Battery Widget

struct BatteryIdleWidget: View {
    @ObservedObject private var battery = BatteryStatusViewModel.shared
    let size: CGFloat

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: batteryIcon)
                .font(.system(size: size * 0.55, weight: .light))
                .foregroundStyle(batteryColor)
            Text("\(Int(battery.levelBattery))%")
                .font(.system(size: 7, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(batteryColor)
        }
        .frame(width: size)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var batteryIcon: String {
        if battery.isCharging { return "battery.100.bolt" }
        let level = Int(battery.levelBattery)
        if level > 75 { return "battery.100" }
        if level > 50 { return "battery.75" }
        if level > 25 { return "battery.50" }
        if level > 10 { return "battery.25" }
        return "battery.0"
    }

    private var batteryColor: Color {
        if battery.isInLowPowerMode { return .yellow }
        if battery.levelBattery <= 20 && !battery.isCharging { return .red }
        if battery.isCharging || battery.isPluggedIn { return .green }
        return .white
    }
}

// MARK: - Bluetooth Widget

struct BluetoothIdleWidget: View {
    @ObservedObject private var bt = BluetoothBatteryManager.shared
    let size: CGFloat

    var body: some View {
        Group {
            if let device = bt.primaryDevice {
                VStack(spacing: 1) {
                    Image(systemName: device.model.sfSymbolName)
                        .font(.system(size: size * 0.5, weight: .light))
                        .foregroundStyle(.white)
                    Text(device.batteryLevel >= 0 ? "\(device.batteryLevel)%" : "–")
                        .font(.system(size: 7, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                }
            } else {
                Image(systemName: "headphones")
                    .font(.system(size: size * 0.6, weight: .light))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        .frame(width: size)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .onAppear { BluetoothBatteryManager.shared.start() }
        .onDisappear { BluetoothBatteryManager.shared.stop() }
    }
}

// MARK: - Next Event Widget

struct NextEventIdleWidget: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    let size: CGFloat

    private var nextEvent: EventModel? {
        calendarManager.events
            .filter { !$0.isAllDay && $0.start > Date() }
            .min(by: { $0.start < $1.start })
    }

    var body: some View {
        Group {
            if let event = nextEvent {
                VStack(spacing: 1) {
                    Image(systemName: "calendar")
                        .font(.system(size: size * 0.5, weight: .light))
                        .foregroundStyle(.white)
                    Text(timeString(from: event.start))
                        .font(.system(size: 7, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                }
            } else {
                Image(systemName: "calendar")
                    .font(.system(size: size * 0.6, weight: .light))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        .frame(width: size)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }

    private func timeString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f.string(from: date)
    }
}

// MARK: - Temperature Widget

struct TemperatureIdleWidget: View {
    @ObservedObject private var thermal = ThermalManager.shared
    let size: CGFloat

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: "thermometer.medium")
                .font(.system(size: size * 0.5, weight: .light))
                .foregroundStyle(tempColor)
            Text(thermal.cpuTemp > 0 ? "\(Int(thermal.cpuTemp))°" : "–")
                .font(.system(size: 7, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(tempColor)
        }
        .frame(width: size)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var tempColor: Color {
        if thermal.cpuTemp > 85 { return .red }
        if thermal.cpuTemp > 70 { return .orange }
        return .white
    }
}

// MARK: - Claude Usage Widget

struct ClaudeUsageIdleWidget: View {
    @ObservedObject private var manager = ClaudeUsageManager.shared
    let size: CGFloat

    var body: some View {
        Group {
            if manager.isAuthenticated {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1.5)
                    Circle()
                        .trim(from: 0, to: manager.usagePercent)
                        .stroke(usageColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.smooth, value: manager.usagePercent)
                    Image(systemName: "apple.intelligence")
                        .font(.system(size: size * 0.38))
                        .foregroundStyle(usageColor)
                }
            } else {
                Image(systemName: "apple.intelligence")
                    .font(.system(size: size * 0.6, weight: .light))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        .frame(width: size, height: size)
    }

    private var usageColor: Color {
        let pct = manager.usagePercent * 100
        if pct >= 90 { return .red }
        if pct >= 75 { return .orange }
        return .white
    }
}

// MARK: - Time Widget

struct TimeIdleWidget: View {
    let size: CGFloat

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 30)) { tl in
            VStack(spacing: 1) {
                Image(systemName: "clock")
                    .font(.system(size: size * 0.5, weight: .light))
                    .foregroundStyle(.white)
                Text(timeString(from: tl.date))
                    .font(.system(size: 7, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(width: size)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
    }

    private func timeString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f.string(from: date)
    }
}
