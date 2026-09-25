//
//  WhatsNewView.swift
//  DynamicNotch
//
//  Created by Mark Greene on 2026-09-20.
//

import SwiftUI

struct WhatsNewView: View {
    let pages: [WhatsNewPage]
    let onFinish: () -> Void
    let onOpenSettings: (String) -> Void

    @State private var index = 0
    @State private var migrationConfirmed = false
    @State private var migrationCommandCopied = false
    @State private var migrationCheckError: String? = nil
    // Shared with Settings: an install started from either place shows "Installing…"
    // in both, since the old daemon really is killed the moment this starts.
    @ObservedObject private var daemonClient = ThermalDaemonClient.shared

    var body: some View {
        ZStack {
            if pages.indices.contains(index) {
                page(pages[index])
                    .id(pages[index].id)
                    .transition(.opacity)
            }
        }
        .frame(width: 400, height: 600)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }

    @ViewBuilder
    private func page(_ page: WhatsNewPage) -> some View {
        VStack(spacing: 20) {
            Text("New in \(page.version)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 32)

            Image(systemName: page.highlight.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 70, height: 56)
                .foregroundColor(.effectiveAccent)

            Text(page.highlight.title)
                .font(.title)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text(page.highlight.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            if let action = page.highlight.action {
                actionButton(action)
            }

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func actionButton(_ action: WhatsNewAction) -> some View {
        switch action {
        case .settings(let tab, let label):
            Button(label) {
                onOpenSettings(tab)
                advance()
            }
            .buttonStyle(.borderedProminent)
            .tint(.effectiveAccent)

        case .link(let url, let label):
            Button(label) {
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
            .tint(.effectiveAccent)

        case .permission(let kind, let label):
            Button(label) {
                Task {
                    await PermissionRequester.request(kind)
                    advance()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.effectiveAccent)

        case .thermalDaemonMigrate:
            migrationContent
        }
    }

    @ViewBuilder
    private var migrationContent: some View {
        VStack(spacing: 12) {
            if daemonClient.isInstalling {
                ProgressView("Installing…")
            } else if migrationCommandCopied {
                VStack(spacing: 6) {
                    Text("Command copied to clipboard.")
                        .font(.caption).bold()
                    Text("In Terminal, press ⌘V then Enter. Takes ~15s to compile. Then click Check Again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button("Check Again") {
                    _ = ThermalDaemonClient.shared.checkAvailability()
                    if !ThermalDaemonClient.migrationNeeded {
                        migrationConfirmed = true
                        advance()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.effectiveAccent)
            } else {
                Button("Update Now") {
                    runMigrationInstall()
                }
                .buttonStyle(.borderedProminent)
                .tint(.effectiveAccent)
            }
            if let error = migrationCheckError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    /// True while the current page is the thermal daemon migration gate and it hasn't
    /// been confirmed yet - hides Skip and disables Next/Done so it can't be dismissed
    /// without actually resolving it.
    private var currentPageBlocksProgress: Bool {
        guard pages.indices.contains(index) else { return false }
        if case .thermalDaemonMigrate = pages[index].highlight.action {
            return !migrationConfirmed
        }
        return false
    }

    private var footer: some View {
        VStack(spacing: 16) {
            if pages.count > 1 {
                HStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == index ? Color.effectiveAccent : Color.secondary.opacity(0.3))
                            .frame(width: i == index ? 16 : 6, height: 6)
                    }
                }
            }

            HStack {
                if pages.count > 1 && !currentPageBlocksProgress {
                    Button("Skip") { onFinish() }
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button(index == pages.count - 1 ? "Done" : "Next") {
                    advance()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(currentPageBlocksProgress)
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 24)
    }

    private func advance() {
        if index == pages.count - 1 {
            onFinish()
        } else {
            withAnimation(.easeInOut(duration: 0.6)) {
                index += 1
            }
        }
    }

    private func runMigrationInstall() {
        migrationCheckError = nil
        Task {
            switch await ThermalDaemonClient.Installer.run() {
            case .installed:
                // do shell script exiting 0 doesn't guarantee the daemon actually came up
                // with the new protocol version, so still verify before advancing.
                _ = ThermalDaemonClient.shared.checkAvailability()
                if !ThermalDaemonClient.migrationNeeded {
                    migrationConfirmed = true
                    advance()
                } else {
                    migrationCheckError = "Ran, but the daemon isn't reporting the new version yet. Try Check Again in a moment."
                    migrationCommandCopied = true
                }
            case .cancelled:
                break
            case .fellBackToTerminal:
                migrationCommandCopied = true
            case .failed(let message):
                migrationCheckError = message
            }
        }
    }
}

#Preview("Multi-page") {
    WhatsNewView(
        pages: [
            WhatsNewPage(version: "27.3", highlight: WhatsNewHighlight(
                id: "extensions",
                icon: "bolt.badge.a",
                title: "Automate with Extensions",
                body: "Describe a small automation — like turning Caffeine on when Xcode is frontmost — and DynamicNotch will run it every time.",
                action: .settings(tab: "Extensions", label: "Open Extensions")
            )),
            WhatsNewPage(version: "27.3", highlight: WhatsNewHighlight(
                id: "aiUsagePromotion",
                icon: "apple.intelligence",
                title: "AI Usage, Front and Center",
                body: "Usage alerts now get promoted so they're harder to miss.",
                action: nil
            )),
        ],
        onFinish: {},
        onOpenSettings: { _ in }
    )
}

#Preview("Single page") {
    WhatsNewView(
        pages: [
            WhatsNewPage(version: "27.3", highlight: WhatsNewHighlight(
                id: "extensions",
                icon: "bolt.badge.a",
                title: "Automate with Extensions",
                body: "Describe a small automation — like turning Caffeine on when Xcode is frontmost — and DynamicNotch will run it every time.",
                action: .settings(tab: "Extensions", label: "Open Extensions")
            )),
        ],
        onFinish: {},
        onOpenSettings: { _ in }
    )
}
