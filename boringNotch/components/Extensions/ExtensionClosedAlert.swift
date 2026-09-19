//
//  ExtensionClosedAlert.swift
//  boringNotch
//
//  Generic closed-notch banner for the `notification.showInApp` action —
//  same visual shape as ThermalClosedAlert (components/Thermal/ThermalView.swift),
//  just parameterized (icon/title/message) instead of hardcoded to temperature.
//

import SwiftUI

struct ExtensionClosedAlert: View {
    @EnvironmentObject var vm: BoringViewModel
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .imageScale(.small)
                    .foregroundStyle(.white)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - 20)

            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
        }
    }
}
