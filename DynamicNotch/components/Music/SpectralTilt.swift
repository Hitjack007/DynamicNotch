import Accelerate
import Foundation

/// Precomputed +N dB/octave spectral tilt weights, applied per-bin in the linear
/// magnitude domain BEFORE dB conversion.
///
/// Music energy naturally rolls off at −3 dB/octave (1/f). A +4.5 dB/oct boost
/// counteracts this so high-frequency content (cymbals, hi-hats) remains visually
/// active without over-boosting. Weighting in linear space before log conversion
/// is the dimensionally correct order — multiplying a linear factor into a dB value
/// is incoherent and distorts dynamic range.
struct SpectralTilt {
    /// Per-bin linear multiplier indexed to match FFT magnitude bins.
    let weights: [Float]

    /// - Parameters:
    ///   - binCount: FFT magnitude bin count (N/2).
    ///   - sampleRate: Capture sample rate in Hz.
    ///   - bufferSize: FFT window size N (not N/2).
    ///   - tiltAmountDB: Slope in dB/octave. 0 dB reference at 1 kHz.
    init(binCount: Int, sampleRate: Float, bufferSize: Int, tiltAmountDB: Float = 4.5) {
        weights = (0..<binCount).map { bin in
            let hz = max(Float(bin) * sampleRate / Float(bufferSize), 1.0)
            let dB = tiltAmountDB * log2(hz / 1000.0)
            return pow(10.0, dB / 20.0)
        }
    }

    /// Multiply tilt weights into linear FFT magnitudes.
    func apply(magnitudes: [Float]) -> [Float] {
        var result = [Float](repeating: 0, count: magnitudes.count)
        vDSP_vmul(magnitudes, 1, weights, 1, &result, 1, vDSP_Length(magnitudes.count))
        return result
    }
}
