//
//  FeatureHighlightView.swift
//  DynamicNotch
//
//  Created by Mark Greene on 2026-09-20.
//

import SwiftUI

/// An onboarding step that tours a feature, reusing the same `WhatsNewHighlight` content
/// shown in the post-update What's New flow. Visually mirrors `PermissionRequestView`.
struct FeatureHighlightView: View {
    let highlight: WhatsNewHighlight
    let onContinue: () -> Void
    let onOpenSettings: (String) -> Void

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: highlight.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 70, height: 56)
                .foregroundColor(.effectiveAccent)
                .padding(.top, 32)

            Text(highlight.title)
                .font(.title)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text(highlight.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack {
                Button("Continue") { onContinue() }
                    .buttonStyle(.bordered)

                if let action = highlight.action {
                    actionButton(action)
                }
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }

    @ViewBuilder
    private func actionButton(_ action: WhatsNewAction) -> some View {
        switch action {
        case .settings(let tab, let label):
            Button(label) {
                onOpenSettings(tab)
                onContinue()
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
                    onContinue()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.effectiveAccent)

        case .thermalDaemonMigrate:
            // Never actually reachable here: this action only appears on a highlight
            // synthesized at launch and shown via WhatsNewView, never looked up by id
            // for onboarding reuse (a fresh install can't have the daemon installed).
            EmptyView()
        }
    }
}

#Preview {
    FeatureHighlightView(
        highlight: WhatsNewCatalog.highlight(id: "extensions"),
        onContinue: {},
        onOpenSettings: { _ in }
    )
}
