import Accelerate
import CoreMedia
import Foundation
import ScreenCaptureKit

// MARK: - Public interface (main-actor)

@MainActor
final class SpectrumAnalyzer: NSObject, ObservableObject {
    static let shared = SpectrumAnalyzer()

    @Published var bandLevels: [Float] = [Float](repeating: 0, count: 6)
    @Published var isCapturing: Bool = false

    // nonisolated let so the SCStreamOutput callback (nonisolated) can reach it
    nonisolated let processor: AudioSignalProcessor

    private var captureStream: SCStream?
    private var stopTask: Task<Void, Never>?

    private override init() {
        processor = AudioSignalProcessor(bandCount: 6, bufferSize: 1024, sampleRate: 44100)
        super.init()
    }

    /// Schedule a stop after a delay, cancellable if start() is called in the meantime.
    /// Use this from onDisappear so transient HUDs don't interrupt the stream.
    func scheduleStop(after seconds: Double = 5) {
        stopTask?.cancel()
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.stop()
        }
    }

    func start() async {
        stopTask?.cancel()   // Cancel any pending delayed stop before restarting
        stopTask = nil
        guard !isCapturing else { return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            return
        }
        do {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else { return }

            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 44100
            config.channelCount = 1
            // Minimal video (required to start the stream; frames are ignored)
            config.width = 2
            config.height = 2

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            let callbackQueue = DispatchQueue(label: "com.boringnotch.spectrum.callback", qos: .userInteractive)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: callbackQueue)
            try await stream.startCapture()
            captureStream = stream
            isCapturing = true
        } catch {
            // Permission denied or hardware unavailable — bars stay at minimum
        }
    }

    func stop() async {
        guard let s = captureStream else { return }
        try? await s.stopCapture()
        captureStream = nil
        isCapturing = false
        bandLevels = [Float](repeating: 0, count: 6)
    }
}

// MARK: - SCStreamOutput (nonisolated — runs on stream's callback queue)

extension SpectrumAnalyzer: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio else { return }
        processor.processBuffer(sampleBuffer) { [weak self] levels in
            Task { @MainActor [weak self] in
                self?.bandLevels = levels
            }
        }
    }
}

// MARK: - Signal processor (owns FFT, mel, envelope state; thread-safe via serial queue)

final class AudioSignalProcessor: @unchecked Sendable {

    private let queue = DispatchQueue(label: "com.boringnotch.spectrum.dsp", qos: .userInteractive)

    private var envelopes: [EnvelopeFollower]
    private var filterbank: MelFilterbank
    private var tilt: SpectralTilt
    private var fftSetup: FFTSetup?
    private var window: [Float]

    let bandCount: Int
    private let bufferSize: Int
    private let log2n: vDSP_Length
    private let sampleRate: Float
    private let noiseFloor: Float = -60
    private let ceiling: Float = 0

    // Per-band release times: bass fast (kick drums don't smear),
    // mids slowest (chords/vocals hold their shape), highs medium.
    private static let releaseTimes: [Float] = [
        0.150,  // Band 1 — sub-bass
        0.180,  // Band 2 — bass
        0.280,  // Band 3 — low mids
        0.350,  // Band 4 — mids (slowest — holds vocal content)
        0.300,  // Band 5 — upper mids
        0.220,  // Band 6 — presence
    ]

    init(bandCount: Int, bufferSize: Int, sampleRate: Float) {
        self.bandCount = bandCount
        self.bufferSize = bufferSize
        self.sampleRate = sampleRate
        self.log2n = vDSP_Length(log2(Double(bufferSize)))

        let times = AudioSignalProcessor.releaseTimes
        envelopes = (0..<bandCount).map { i in
            EnvelopeFollower(releaseTime: i < times.count ? times[i] : 0.220)
        }
        filterbank = MelFilterbank(
            bandCount: bandCount,
            fftBinCount: bufferSize / 2,
            sampleRate: sampleRate,
            minHz: 80,
            maxHz: 16000
        )
        tilt = SpectralTilt(
            binCount: bufferSize / 2,
            sampleRate: sampleRate,
            bufferSize: bufferSize,
            tiltAmountDB: 4.5
        )

        var w = [Float](repeating: 0, count: bufferSize)
        vDSP_hann_window(&w, vDSP_Length(bufferSize), Int32(vDSP_HANN_NORM))
        window = w

        fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Double(bufferSize))), FFTRadix(kFFTRadix2))
    }

    deinit {
        if let setup = fftSetup { vDSP_destroy_fftsetup(setup) }
    }

    /// Extract samples on the calling thread before the buffer is recycled, then process async.
    func processBuffer(_ sampleBuffer: CMSampleBuffer, completion: @escaping ([Float]) -> Void) {
        guard let samples = extractFloat32Samples(from: sampleBuffer) else { return }
        queue.async { [weak self] in
            guard let self else { return }
            completion(self.runPipeline(samples: samples))
        }
    }

    // MARK: - CMSampleBuffer extraction

    private func extractFloat32Samples(from sampleBuffer: CMSampleBuffer) -> [Float]? {
        var ablSizeNeeded = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: &ablSizeNeeded,
            bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: 0, blockBufferOut: nil
        )
        guard ablSizeNeeded > 0 else { return nil }

        let rawPtr = UnsafeMutableRawPointer.allocate(byteCount: ablSizeNeeded, alignment: 16)
        defer { rawPtr.deallocate() }

        var retainedBlockBuffer: CMBlockBuffer?
        let ablPtr = rawPtr.bindMemory(to: AudioBufferList.self, capacity: 1)

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: ablPtr,
            bufferListSize: ablSizeNeeded,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &retainedBlockBuffer
        )
        guard status == noErr else { return nil }

        var samples: [Float] = []
        for buffer in UnsafeMutableAudioBufferListPointer(ablPtr) {
            guard let data = buffer.mData else { continue }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size
            samples += Array(UnsafeBufferPointer(
                start: data.bindMemory(to: Float32.self, capacity: count),
                count: count
            ))
        }
        return samples.isEmpty ? nil : samples
    }

    // MARK: - DSP pipeline (internal for testability via @testable import)

    func runPipeline(samples: [Float]) -> [Float] {
        guard let setup = fftSetup else { return [Float](repeating: 0, count: bandCount) }
        let n = bufferSize

        // Most recent n samples, zero-padded if shorter than one full frame
        var frame = [Float](repeating: 0, count: n)
        let tail = samples.suffix(n)
        let offset = n - tail.count
        for (i, v) in tail.enumerated() { frame[offset + i] = v }

        // Step 2 — Hann window to reduce spectral leakage
        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(n))

        // Step 2 (cont.) — FFT; stable pointer closures avoid dangling-pointer warnings
        var realParts = [Float](repeating: 0, count: n / 2)
        var imagParts = [Float](repeating: 0, count: n / 2)
        var magnitudes = [Float](repeating: 0, count: n / 2)

        realParts.withUnsafeMutableBufferPointer { realBuf in
            imagParts.withUnsafeMutableBufferPointer { imagBuf in
                windowed.withUnsafeBufferPointer { winBuf in
                    winBuf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { cPtr in
                        var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                        vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

                var scale = Float(1.0) / Float(2 * n)
                vDSP_vsmul(realBuf.baseAddress!, 1, &scale, realBuf.baseAddress!, 1, vDSP_Length(n / 2))
                vDSP_vsmul(imagBuf.baseAddress!, 1, &scale, imagBuf.baseAddress!, 1, vDSP_Length(n / 2))

                magnitudes.withUnsafeMutableBufferPointer { magBuf in
                    split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                    vDSP_zvabs(&split, 1, magBuf.baseAddress!, 1, vDSP_Length(n / 2))
                }
            }
        }

        // Step 3 — Spectral tilt in linear magnitude domain (before dB conversion)
        let tilted = tilt.apply(magnitudes: magnitudes)

        // Step 4 — dB conversion (amplitude mode: 20·log10) then clamp and normalise to [0, 1]
        // Flag 1 = amplitude/voltage mode. Magnitudes from vDSP_zvabs are linear amplitudes,
        // so 20·log10 is correct. Flag 0 (power: 10·log10) halves the dB range and compresses
        // all bands into 0.5–0.9, making them indistinguishable.
        var dB = [Float](repeating: 0, count: n / 2)
        var one: Float = 1.0
        vDSP_vdbcon(tilted, 1, &one, &dB, 1, vDSP_Length(n / 2), 1)

        var lo = noiseFloor, hi = ceiling
        vDSP_vclip(dB, 1, &lo, &hi, &dB, 1, vDSP_Length(n / 2))
        let range = ceiling - noiseFloor
        let normalized = dB.map { ($0 - noiseFloor) / range }

        // Step 5 — Mel filterbank (80–16000 Hz; weights sum=1 → weighted average ∈ [0, 1])
        let melBands = filterbank.apply(magnitudes: normalized)

        // Step 6 — Per-band instant attack / exponential release
        let dt = Float(n) / sampleRate
        var levels = [Float](repeating: 0, count: bandCount)
        for i in 0..<min(bandCount, melBands.count) {
            levels[i] = envelopes[i].process(input: melBands[i], dt: dt)
        }
        return levels
    }
}
