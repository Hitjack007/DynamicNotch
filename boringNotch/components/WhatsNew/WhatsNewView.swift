//
//  WhatsNewView.swift
//  boringNotch
//
//  Created by Mark Greene on 2026-09-20.
//

import SwiftUI

struct WhatsNewView: View {
    let pages: [WhatsNewPage]
    let onFinish: () -> Void
    let onOpenSettings: (String) -> Void

    @State private var index = 0

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
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
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
        }
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
                if pages.count > 1 {
                    Button("Skip") { onFinish() }
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button(index == pages.count - 1 ? "Done" : "Next") {
                    advance()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
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
