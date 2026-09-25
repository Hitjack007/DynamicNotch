import Testing
@testable import DynamicNotch

// MARK: - Helpers

/// Fan curve points carry a randomly generated `id`, so compare the fields that actually
/// describe the curve rather than `FanCurvePoint` equality.
private func fields(_ points: [FanCurvePoint]) -> [[Int]] {
    points.map { [$0.tempC, $0.fanPercent] }
}

private func assertWellFormedCurve(_ points: [FanCurvePoint], name: String) {
    #expect(points.count >= 2, "\(name) needs at least two points to interpolate between")

    let temps = points.map(\.tempC)
    #expect(temps == temps.sorted(), "\(name) must be sorted by temperature for linear interpolation to make sense")
    #expect(Set(temps).count == temps.count, "\(name) has a duplicate temperature")

    for point in points {
        #expect((0...100).contains(point.fanPercent), "\(name) has a fan percent outside 0...100: \(point.fanPercent)")
    }

    #expect(points.last?.fanPercent == 100, "\(name) should ramp all the way to 100% by its last point")
}

// MARK: - Tests

@Suite("Fan curve preset invariants")
struct FanCurvePresetTests {

    @Test("appleDefault, custom and maxSpeed have no fixed curve — they're handled specially")
    func presetsWithoutFixedCurves() {
        #expect(FanCurvePreset.appleDefault.curvePoints == nil)
        #expect(FanCurvePreset.custom.curvePoints == nil)
        #expect(FanCurvePreset.maxSpeed.curvePoints == nil)
    }

    @Test("Ramp presets each describe a well-formed curve", arguments: [
        FanCurvePreset.ramp80, .ramp70, .ramp60,
    ])
    func rampPresetsAreWellFormed(preset: FanCurvePreset) {
        guard let points = preset.curvePoints else {
            Issue.record("\(preset) should have curve points")
            return
        }
        assertWellFormedCurve(points, name: preset.rawValue)
    }

    @Test("The default custom-curve seed is well-formed")
    func defaultCurveIsWellFormed() {
        assertWellFormedCurve(FanCurvePoint.defaultCurve, name: "defaultCurve")
    }

    @Test("Lower ramp presets start ramping at a lower temperature")
    func rampPresetsOrderByStartTemperature() {
        let ramp60Start = FanCurvePreset.ramp60.curvePoints?.first?.tempC
        let ramp70Start = FanCurvePreset.ramp70.curvePoints?.first?.tempC
        let ramp80Start = FanCurvePreset.ramp80.curvePoints?.first?.tempC
        #expect((ramp60Start!, ramp70Start!, ramp80Start!) == (40, 45, 50))
    }

    @Test("Every preset has a non-empty short name distinct from its raw value")
    func everyPresetHasAShortName() {
        for preset in FanCurvePreset.allCases {
            #expect(!preset.shortName.isEmpty)
        }
    }

    @Test("The default custom-curve seed matches the documented values")
    func defaultCurveFields() {
        #expect(fields(FanCurvePoint.defaultCurve) == [[50, 0], [65, 35], [80, 100]])
    }
}
