//
//  SpectrogramSetupView.swift
//  boringNotch
//
//  Created by Mark Greene on 2026-08-29.
//

import SwiftUI
import Defaults

struct SpectrogramSetupView: View {
    let onContinue: () -> Void

    @Default(.useResponsiveSpectrogram) var useResponsiveSpectrogram
    @Default(.spectrogramTitleExclusions) var spectrogramTitleExclusions
    @Default(.spectrogramAppExclusions) var spectrogramAppExclusions

    @State private var selectedKeywords: Set<String> = Set(Self.defaultKeywords)
    @State private var installedApps: [(name: String, bundleID: String, icon: NSImage?)] = []
    @State private var selectedBundleIDs: Set<String> = []

    static let defaultKeywords = ["Netflix", "Disney+", "Hulu", "Prime Video", "Max", "Paramount+", "Peacock"]

    static let candidateApps: [(name: String, bundleID: String)] = [
        ("Apple TV", "com.apple.TV"),
        ("Apple Music", "com.apple.Music"),
        ("Apple Books", "com.apple.iBooksX"),
        ("1Password", "com.1password.1password"),
        ("Passwords", "com.apple.Passwords"),
        ("Photos", "com.apple.Photos"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "waveform")
                .font(.system(size: 52))
                .foregroundColor(.effectiveAccent)
                .padding(.top, 28)
                .padding(.bottom, 12)

            Text("Responsive Spectrogram")
                .font(.title)
                .fontWeight(.semibold)

            Text("The music visualizer can react to your actual system audio using the Screen Recording permission you just granted.")
                .multilineTextAlignment(.center)
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.horizontal, 28)
                .padding(.top, 8)

            Toggle("Enable responsive spectrogram", isOn: $useResponsiveSpectrogram)
                .toggleStyle(.switch)
                .padding(.horizontal, 28)
                .padding(.top, 20)

            if useResponsiveSpectrogram {
                Divider()
                    .padding(.horizontal, 28)
                    .padding(.top, 16)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Protect DRM content")
                        .font(.headline)
                    Text("Some apps pause when screen recording is active. The spectrogram switches to the static animation for these automatically.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("STREAMING SITES")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                            .padding(.top, 4)

                        ForEach(Self.defaultKeywords, id: \.self) { keyword in
                            SpectrogramExclusionRow(
                                label: keyword,
                                subtitle: "title keyword",
                                appIcon: nil,
                                isSelected: selectedKeywords.contains(keyword)
                            ) {
                                if selectedKeywords.contains(keyword) {
                                    selectedKeywords.remove(keyword)
                                } else {
                                    selectedKeywords.insert(keyword)
                                }
                            }
                        }

                        if !installedApps.isEmpty {
                            Text("INSTALLED APPS")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .padding(.leading, 4)
                                .padding(.top, 8)

                            ForEach(installedApps, id: \.bundleID) { app in
                                SpectrogramExclusionRow(
                                    label: app.name,
                                    subtitle: app.bundleID,
                                    appIcon: app.icon,
                                    isSelected: selectedBundleIDs.contains(app.bundleID)
                                ) {
                                    if selectedBundleIDs.contains(app.bundleID) {
                                        selectedBundleIDs.remove(app.bundleID)
                                    } else {
                                        selectedBundleIDs.insert(app.bundleID)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 230)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer(minLength: 0)

            Button("Continue") {
                applySelections()
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.25), value: useResponsiveSpectrogram)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
        .task {
            await loadInstalledApps()
        }
    }

    private func loadInstalledApps() async {
        var found: [(name: String, bundleID: String, icon: NSImage?)] = []
        for candidate in Self.candidateApps {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate.bundleID) else { continue }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            found.append((name: candidate.name, bundleID: candidate.bundleID, icon: icon))
        }
        installedApps = found
        selectedBundleIDs = Set(found.map { $0.bundleID })
    }

    private func applySelections() {
        guard useResponsiveSpectrogram else { return }
        for keyword in selectedKeywords where !spectrogramTitleExclusions.contains(keyword) {
            spectrogramTitleExclusions.append(keyword)
        }
        for bundleID in selectedBundleIDs where !spectrogramAppExclusions.contains(bundleID) {
            spectrogramAppExclusions.append(bundleID)
        }
    }
}

struct SpectrogramExclusionRow: View {
    let label: String
    let subtitle: String
    let appIcon: NSImage?
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 18))
                        .frame(width: 28, height: 28)
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.body)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundColor(isSelected ? .effectiveAccent : .secondary.opacity(0.4))
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.effectiveAccent.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.effectiveAccent.opacity(0.4) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }
}

#Preview {
    SpectrogramSetupView(onContinue: {})
        .frame(width: 400, height: 600)
}
