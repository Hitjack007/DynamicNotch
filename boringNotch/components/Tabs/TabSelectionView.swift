//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @AppStorage("showThermalTab") private var showThermalTab: Bool = true
    @AppStorage("showSystemStatsTab") private var showSystemStatsTab: Bool = false
    @Namespace var animation
    @State private var hapticTrigger = false

    private var tabs: [TabModel] {
        var result: [TabModel] = [
            TabModel(label: "Home", icon: "house.fill", view: .home),
            TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
        ]
        if showThermalTab     { result.append(TabModel(label: "Thermal", icon: "thermometer.medium", view: .thermal)) }
        if showSystemStatsTab { result.append(TabModel(label: "Stats",   icon: "cpu",                view: .systemStats)) }
        return result
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                    withAnimation(.smooth) {
                        coordinator.currentView = tab.view
                    }
                }
                .frame(height: 26)
                .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                .background {
                    if tab.view == coordinator.currentView {
                        Capsule()
                            .fill(Color(nsColor: .secondarySystemFill))
                            .matchedGeometryEffect(id: "capsule", in: animation)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                            .matchedGeometryEffect(id: "capsule", in: animation)
                            .hidden()
                    }
                }
            }
        }
        .clipShape(Capsule())
        .background(TabScrollHandler(
            onScrollRight: { switchTab(forward: false) },
            onScrollLeft:  { switchTab(forward: true)  }
        ))
        .sensoryFeedback(.alignment, trigger: hapticTrigger)
    }

    // forward=true → next tab (higher index); forward=false → previous tab (lower index)
    private func switchTab(forward: Bool) {
        let currentTabs = tabs
        guard let idx = currentTabs.firstIndex(where: { $0.view == coordinator.currentView }) else { return }
        let newIdx = forward ? idx + 1 : idx - 1
        guard newIdx >= 0 && newIdx < currentTabs.count else { return }
        withAnimation(.smooth) {
            coordinator.currentView = currentTabs[newIdx].view
        }
        if Defaults[.enableHaptics] { hapticTrigger.toggle() }
    }
}

// MARK: - Position-aware tab scroll handler

private struct TabScrollHandler: NSViewRepresentable {
    var onScrollRight: () -> Void   // user swiped right → go to previous tab
    var onScrollLeft:  () -> Void   // user swiped left  → go to next tab

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onScrollRight = onScrollRight
        context.coordinator.onScrollLeft  = onScrollLeft
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScrollRight: onScrollRight, onScrollLeft: onScrollLeft)
    }

    @MainActor final class Coordinator: NSObject {
        var onScrollRight: () -> Void
        var onScrollLeft:  () -> Void

        // 25 pt of horizontal scroll to commit a tab switch; snappy but not hair-trigger
        private let threshold: CGFloat = 25
        private let noiseFloor: CGFloat = 0.5
        private var monitor: Any?
        private weak var view: NSView?
        private var accumulated: CGFloat = 0
        private var hasFired = false
        private var endTask: Task<Void, Never>?

        init(onScrollRight: @escaping () -> Void, onScrollLeft: @escaping () -> Void) {
            self.onScrollRight = onScrollRight
            self.onScrollLeft  = onScrollLeft
        }

        func install(on view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func remove() {
            if let m = monitor { NSEvent.removeMonitor(m) }
            monitor = nil
            endTask?.cancel()
            endTask = nil
        }

        private func handle(_ event: NSEvent) {
            guard let view, view.window != nil else { return }

            // Only fire when the cursor is actually over the tab bar
            let mouse = event.locationInWindow
            let frameInWindow = view.convert(view.bounds, to: nil)
            guard frameInWindow.contains(mouse) else { return }

            // Reset state on gesture end (including momentum end)
            if event.phase == .ended || event.momentumPhase == .ended {
                accumulated = 0
                hasFired = false
                endTask?.cancel()
                return
            }

            // Skip vertically-dominant scrolls (e.g. scrolling the shelf)
            let absDX = abs(event.scrollingDeltaX)
            let absDY = abs(event.scrollingDeltaY)
            guard absDX >= 1.5 * absDY else { return }

            // Mouse wheel events arrive as large discrete steps; scale so they
            // feel similar to trackpad swipes.
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 8
            let delta = event.scrollingDeltaX * scale
            guard abs(delta) > noiseFloor else { return }

            if !hasFired {
                accumulated += delta
                if abs(accumulated) >= threshold {
                    hasFired = true  // lock: one switch per gesture, no wrap-around
                    if accumulated > 0 {
                        onScrollRight()
                    } else {
                        onScrollLeft()
                    }
                }
            }

            // Fall back to a timeout in case the phase-ended event is missed
            endTask?.cancel()
            endTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                self?.accumulated = 0
                self?.hasFired = false
            }
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
