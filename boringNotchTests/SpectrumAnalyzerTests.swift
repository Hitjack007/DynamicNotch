import Testing
import AVFoundation
@testable import DynamicNotch

// MARK: - Helpers

private func makeProcessor() -> AudioSignalProcessor {
    AudioSignalProcessor(bandCount: 6, bufferSize: 1024, sampleRate: 44100)
}

private func sineWave(hz: Float, count: Int = 1024, sampleRate: Float = 44100) -> [Float] {
    (0..<count).map { i in sin(2.0 * Float.pi * hz * Float(i) / sampleRate) }
}

private func impulse(count: Int = 1024) -> [Float] {
    var buf = [Float](repeating: 0, count: count)
    buf[count / 2] = 1.0  // Center where Hann window peaks at ≈ 1.0; w[0] = 0 kills edge spikes
    return buf
}

// MARK: - Tests

@Suite("Spectrum DSP")
struct SpectrumAnalyzerTests {

    @Test("100 Hz sine: Band 1 (sub-bass) active, Bands 5–6 near zero")
    func sineAt100Hz() {
        let proc = makeProcessor()
        let levels = proc.runPipeline(samples: sineWave(hz: 100))
        #expect(levels[0] > 0.1,  "Band 1 (sub-bass) should be active for a 100 Hz sine; got \(levels[0])")
        #expect(levels[4] < 0.15, "Band 5 should be near zero for 100 Hz; got \(levels[4])")
        #expect(levels[5] < 0.15, "Band 6 should be near zero for 100 Hz; got \(levels[5])")
    }

    @Test("3000 Hz sine: Band 4 or 5 (mids) active, Band 1 near zero")
    func sineAt3000Hz() {
        let proc = makeProcessor()
        let levels = proc.runPipeline(samples: sineWave(hz: 3000))
        #expect(levels[3] > 0.1 || levels[4] > 0.1,
                "Band 4 or 5 should be active for 3000 Hz sine; got \(levels)")
        #expect(levels[0] < 0.15, "Band 1 (sub-bass) should be near zero for 3000 Hz; got \(levels[0])")
    }

    @Test("Impulse: at least some bands are non-zero in the same frame (instant attack)")
    func impulseInstantAttack() {
        let proc = makeProcessor()
        let levels = proc.runPipeline(samples: impulse())
        #expect(levels.contains { $0 > 0.05 },
                "At least some bands should be non-zero after a unit impulse; got \(levels)")
    }

    @Test("Silence after impulse: bands decay below 0.8 within 6 frames (~140 ms)")
    func decayAfterImpulse() {
        let proc = makeProcessor()
        let silence = [Float](repeating: 0, count: 1024)
        _ = proc.runPipeline(samples: sineWave(hz: 1000))  // prime envelopes with a loud signal
        var levels = [Float](repeating: 0, count: 6)
        for _ in 0..<6 { levels = proc.runPipeline(samples: silence) }
        #expect(levels.allSatisfy { $0 < 0.8 },
                "All bands should decay below 0.8 after 6 silent frames; got \(levels)")
    }

    @Test("Spectral tilt: weight at the bin nearest 1 kHz is within 5% of 1.0")
    func spectralTiltReferencePoint() {
        let sampleRate: Float = 44100
        let bufferSize = 1024
        let tilt = SpectralTilt(binCount: bufferSize / 2, sampleRate: sampleRate, bufferSize: bufferSize, tiltAmountDB: 4.5)
        let bin = Int(1000.0 * Float(bufferSize) / sampleRate)   // ≈ bin 23
        let weight = tilt.weights[bin]
        #expect(abs(weight - 1.0) < 0.05,
                "Tilt weight near 1 kHz should be ≈ 1.0 (got \(weight) at bin \(bin))")
    }

    @Test("Spectral tilt: weights are monotonically increasing (higher frequencies boosted more)")
    func spectralTiltMonotonic() {
        let tilt = SpectralTilt(binCount: 512, sampleRate: 44100, bufferSize: 1024, tiltAmountDB: 4.5)
        #expect(tilt.weights[10]  < tilt.weights[100], "Tilt should boost bin 100 more than bin 10")
        #expect(tilt.weights[100] < tilt.weights[400], "Tilt should boost bin 400 more than bin 100")
    }
}
