//
//  DisplaySetupView.swift
//  DynamicNotch
//
//  Created by Mark Greene on 2026-09-19.
//

import SwiftUI
import Defaults

struct DisplaySetupView: View {
    let onContinue: () -> Void

    @ObservedObject private var coordinator = NotchViewCoordinator.shared
    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) var automaticallySwitchDisplay

    @State private var screens: [(uuid: String, name: String)] = []

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "display.2")
                .font(.system(size: 52))
                .foregroundColor(.effectiveAccent)
                .padding(.top, 28)
                .padding(.bottom, 12)

            Text("Choose Your Displays")
                .font(.title)
                .fontWeight(.semibold)

            Text("DynamicNotch can live on just one screen or follow you across every display you own.")
                .multilineTextAlignment(.center)
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.horizontal, 28)
                .padding(.top, 8)

            Form {
                Toggle("Show on all displays", isOn: $showOnAllDisplays)
                    .onChange(of: showOnAllDisplays) {
                        NotificationCenter.default.post(
                            name: Notification.Name.showOnAllDisplaysChanged, object: nil)
                    }

                Picker("Preferred display", selection: $coordinator.preferredScreenUUID) {
                    ForEach(screens, id: \.uuid) { screen in
                        Text(screen.name).tag(screen.uuid as String?)
                    }
                }
                .disabled(showOnAllDisplays)

                Toggle("Fall back to main display if preferred is unavailable", isOn: $automaticallySwitchDisplay)
                    .onChange(of: automaticallySwitchDisplay) {
                        NotificationCenter.default.post(
                            name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
                    }
                    .disabled(showOnAllDisplays)

                Picker("Show HUD on", selection: Binding(
                    get: { Defaults[.hudDisplayPolicy] },
                    set: { Defaults[.hudDisplayPolicy] = $0 }
                )) {
                    ForEach(HUDDisplayPolicy.allCases) { policy in
                        Text(policy.rawValue).tag(policy)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!showOnAllDisplays)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .padding(.top, 20)

            Text("Each display can customize what shows in its own closed notch afterward, in Settings → Displays.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.top, 4)

            Spacer(minLength: 0)

            Button("Continue") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
        .onAppear {
            refreshScreens()
            // Nothing to choose between with a single display — skip straight through.
            if screens.count <= 1 {
                onContinue()
            }
        }
    }

    private func refreshScreens() {
        screens = NSScreen.screens.compactMap { screen in
            guard let uuid = screen.displayUUID else { return nil }
            return (uuid, screen.localizedName)
        }
    }
}

#Preview {
    DisplaySetupView(onContinue: {})
        .frame(width: 400, height: 600)
}
