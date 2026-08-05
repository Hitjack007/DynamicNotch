import SwiftUI

/// Renders 6 equaliser-style bars driven by envelope-followed band levels.
/// Used as a `.mask {}` on a coloured rectangle — bars are filled white.
///
/// Bars scale from their vertical center (grow up AND down), matching the original
/// AudioSpectrum NSView behaviour (anchorPoint = 0.5, 0.5 + scaleY transform).
///
/// The 0.02 minimum display height is applied here at the view layer only —
/// the signal path returns true zero during silence.
struct SpectrumBarView: View {
    let bandLevels: [Float]  // 0.0–1.0, already envelope-followed

    private let barWidth: CGFloat = 1.5
    private let spacing: CGFloat = 0.7
    private let bufferDuration: Double = 1024.0 / 44100.0

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(Array(bandLevels.enumerated()), id: \.offset) { _, level in
                let display = min(max(level, 0.02) * 1.5, 1.0)
                RoundedRectangle(cornerRadius: 0.75)
                    .frame(width: barWidth)
                    .scaleEffect(y: CGFloat(display), anchor: .center)
                    .animation(.linear(duration: bufferDuration), value: display)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

#Preview {
    SpectrumBarView(bandLevels: [0.3, 0.6, 0.9, 0.7, 0.5, 0.2])
        .frame(width: 16, height: 12)
        .background(.black)
        .padding()
}
