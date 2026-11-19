#if DEBUG
import SwiftUI
import Testing
@testable import DynamicNotch

@MainActor
struct ClosedNotchLayoutTests {
    private let cameraSize = CGSize(width: 192, height: 38)
    private let menuBarSize = CGSize(width: 192, height: 32)
    private let proposal = CGSize(width: 800, height: 300)

    @Test("Closed notch keeps its height across 200 offscreen layout cycles")
    func closedHeightSurvivesLayoutCycles() {
        let model = NotchViewModel()
        defer { model.destroy() }
        model.hideOnClosed = false
        model.setClosedLayout(size: cameraSize)
        let controller = makeController(model)

        for cycle in 1...200 {
            let activity: ContentView.LayoutSample = cycle.isMultiple(of: 2) ? .music : .volume
            let idleHeight = measure(.idle, with: controller, model: model)
            let before = measure(activity, with: controller, model: model)

            model.setOpenLayout()
            let openHeight = measure(.idle, with: controller, model: model)
            model.setClosedLayout(size: cameraSize)
            let after = measure(activity, with: controller, model: model)

            guard idleHeight == cameraSize.height,
                  before == cameraSize.height,
                  openHeight == openNotchSize.height,
                  after == cameraSize.height else {
                Issue.record("Cycle \(cycle), \(activity): idle \(idleHeight), before \(before), open \(openHeight), after \(after)")
                return
            }
        }
    }

    @Test("A simulated short closed height is visible in both activities")
    func measuresSimulatedShortHeight() {
        let model = NotchViewModel()
        defer { model.destroy() }
        model.hideOnClosed = false
        model.setClosedLayout(size: menuBarSize)
        let controller = makeController(model)

        let shortVolume = measure(.volume, with: controller, model: model)
        let shortMusic = measure(.music, with: controller, model: model)
        model.setOpenLayout()
        _ = measure(.idle, with: controller, model: model)
        model.setClosedLayout(size: cameraSize)
        let restoredVolume = measure(.volume, with: controller, model: model)
        let restoredMusic = measure(.music, with: controller, model: model)

        #expect(shortVolume == menuBarSize.height)
        #expect(shortMusic == menuBarSize.height)
        #expect(restoredVolume == cameraSize.height)
        #expect(restoredMusic == cameraSize.height)
    }

    private func makeController(_ model: NotchViewModel) -> NSHostingController<AnyView> {
        NSHostingController(rootView: AnyView(ContentView(layoutSample: .idle).environmentObject(model)))
    }

    private func measure(
        _ sample: ContentView.LayoutSample,
        with controller: NSHostingController<AnyView>,
        model: NotchViewModel
    ) -> CGFloat {
        controller.rootView = AnyView(ContentView(layoutSample: sample).environmentObject(model))
        return controller.sizeThatFits(in: proposal).height
    }
}
#endif
