import Defaults
import SwiftUI

struct DownloadLiveActivity: View {
    @EnvironmentObject var vm: NotchViewModel
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var batteryModel = BatteryStatusViewModel.shared
    @State private var spinAngle: Double = 0

    var body: some View {
        if let dl = downloadManager.activeDownloads.first {
            HStack(spacing: 0) {
                progressRing(for: dl)
                    .padding(.trailing, 6)
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)
                if showsChargingGlyph {
                    ChargingSlotGlyph(size: indicatorSize)
                        .frame(width: indicatorSize * 2.5, alignment: .leading)
                        .padding(.leading, 6)
                } else {
                    fileLabel(for: dl)
                        .padding(.leading, 6)
                }
            }
            .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        }
    }

    private var indicatorSize: CGFloat { max(8, vm.effectiveClosedNotchHeight - 8) }

    /// See `ContentView.showsChargingGlyph` for why this keys off `isCharging`
    /// rather than `isPluggedIn`.
    private var showsChargingGlyph: Bool {
        #if DEBUG
        if batteryModel.debugForceCharging { return true }
        #endif
        return batteryModel.isCharging && Defaults[.showPowerStatusNotifications]
    }

    private func progressRing(for dl: ActiveDownload) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 1.5)

            if dl.progress > 0 {
                Circle()
                    .trim(from: 0, to: dl.progress)
                    .stroke(
                        Color.white,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth, value: dl.progress)
            } else {
                // Indeterminate spinner for unknown progress
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(
                        Color.white.opacity(0.7),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(spinAngle))
                    .onAppear {
                        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                            spinAngle = 360
                        }
                    }
            }

            Image(systemName: "arrow.down")
                .font(.system(size: indicatorSize * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: indicatorSize, height: indicatorSize)
        .overlay(alignment: .topTrailing) {
            let count = downloadManager.activeDownloads.count
            if count > 1 {
                Text("\(count)")
                    .font(.system(size: 6, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 2.5)
                    .background(Color.white, in: Capsule())
                    .offset(x: 3, y: -3)
            }
        }
    }

    private func fileLabel(for dl: ActiveDownload) -> some View {
        Text(dl.fileName)
            .font(.system(size: 9, weight: .regular, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .minimumScaleFactor(0.6)
            .frame(width: indicatorSize * 2.5, alignment: .leading)
    }
}
