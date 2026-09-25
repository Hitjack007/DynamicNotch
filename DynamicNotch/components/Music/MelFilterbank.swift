import Accelerate
import Foundation

/// Mel-scale triangular filterbank.
/// Pure struct — no AVFoundation, fully unit-testable.
struct MelFilterbank {
    let bandCount: Int
    let fftBinCount: Int
    let sampleRate: Float

    private struct BandFilter {
        let startBin: Int
        let weights: [Float]
    }

    private let filters: [BandFilter]

    init(bandCount: Int, fftBinCount: Int, sampleRate: Float, minHz: Float = 80, maxHz: Float? = nil) {
        self.bandCount = bandCount
        self.fftBinCount = fftBinCount
        self.sampleRate = sampleRate

        let nyquist = sampleRate / 2
        let topHz = min(maxHz ?? nyquist, nyquist)

        let melMin = MelFilterbank.hz2mel(minHz)
        let melMax = MelFilterbank.hz2mel(topHz)

        // B+2 anchor frequencies equally spaced in mel domain
        let anchorsHz: [Float] = (0..<bandCount + 2).map { i in
            let mel = melMin + Float(i) * (melMax - melMin) / Float(bandCount + 1)
            return MelFilterbank.mel2hz(mel)
        }

        // Map Hz to nearest FFT bin
        let bins: [Int] = anchorsHz.map { hz in
            max(0, min(fftBinCount - 1, Int((hz / nyquist) * Float(fftBinCount))))
        }

        var result: [BandFilter] = []
        for b in 0..<bandCount {
            let left   = bins[b]
            let center = bins[b + 1]
            let right  = bins[b + 2]
            guard right > left else {
                result.append(BandFilter(startBin: left, weights: []))
                continue
            }
            var weights = [Float](repeating: 0, count: right - left)
            for bin in left..<center {
                weights[bin - left] = Float(bin - left) / Float(max(1, center - left))
            }
            for bin in center..<right {
                weights[bin - left] = Float(right - bin) / Float(max(1, right - center))
            }
            // Normalise to sum=1 so output is a weighted average ∈ [0, 1]
            let weightSum = weights.reduce(0, +)
            if weightSum > 0 {
                let inv = Float(1) / weightSum
                weights = weights.map { $0 * inv }
            }
            result.append(BandFilter(startBin: left, weights: weights))
        }
        self.filters = result
    }

    /// Apply the filterbank to normalised FFT magnitudes, returning the peak
    /// value within each band's bin range.
    ///
    /// Peak (max) is used instead of weighted average because music energy is
    /// concentrated in a few bins. Averaging those against the many near-zero
    /// neighbour bins collapses every band to ~0.05, making bars invisible.
    /// The mel bin ranges still provide correct frequency selectivity.
    func apply(magnitudes: [Float]) -> [Float] {
        var output = [Float](repeating: 0, count: bandCount)
        for (b, filter) in filters.enumerated() {
            guard !filter.weights.isEmpty else { continue }
            let start = filter.startBin
            let end   = min(start + filter.weights.count, magnitudes.count)
            guard end > start else { continue }
            var peak: Float = 0
            vDSP_maxv(Array(magnitudes[start..<end]), 1, &peak, vDSP_Length(end - start))
            output[b] = peak
        }
        return output
    }

    static func hz2mel(_ hz: Float) -> Float { 2595 * log10(1 + hz / 700) }
    static func mel2hz(_ mel: Float) -> Float { 700 * (pow(10, mel / 2595) - 1) }
}
