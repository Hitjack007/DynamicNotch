import Foundation

/// Instant-attack / exponential-release envelope follower.
/// Pure struct — no AVFoundation, fully unit-testable.
///
/// The correct mental model for a visualizer is a peak detector, not a VU meter.
/// Bars must snap upward instantaneously on any transient (instant attack), then
/// decay smoothly. A non-zero attack time constant causes bars to lag behind the
/// beat, making the visualizer feel disconnected from the music.
struct EnvelopeFollower {
    var level: Float = 0

    /// Exponential time constant for the falling phase (seconds).
    var releaseTime: Float

    init(releaseTime: Float = 0.300) {
        self.releaseTime = releaseTime
    }

    /// Update envelope for one audio buffer period. Returns level clamped to [0, 1].
    /// `dt` = bufferSize / sampleRate (≈ 0.023 s at 44100 / 1024).
    mutating func process(input: Float, dt: Float) -> Float {
        if input >= level {
            level = input                          // Instantaneous — locks to every transient
        } else {
            let releaseCoeff = 1.0 - exp(-dt / releaseTime)
            level -= releaseCoeff * (level - input)
        }
        level = max(0, min(1, level))
        return level
    }
}
