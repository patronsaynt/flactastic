import AVFoundation
import Accelerate
import Observation
import os

/// Real-time FFT analyzer driven by an `AVAudioEngine` tap. Decouples audio
/// callbacks from UI redraws: the tap produces an FFT target whenever the
/// hardware delivers a buffer (typically ~10 Hz on macOS), and a 60 Hz timer
/// on the main actor smoothly interpolates `magnitudes` toward that target.
/// SwiftUI redraws every tick, so the bars look fluid even when the audio
/// thread is firing at a low rate.
///
/// Lifecycle: `attach(to:)` installs the tap and starts the display timer;
/// `detach()` tears both down. Keep it detached when no spectrum mode is
/// active to avoid unnecessary FFT cost.
@Observable
@MainActor
final class SpectrumAnalyzer {

    /// Number of output bins exposed to the UI.
    nonisolated static let binCount: Int = 64

    nonisolated private static let fftSize: Int = 1024
    nonisolated private static let log2N: vDSP_Length = vDSP_Length(log2(Double(fftSize)))
    nonisolated private static let historyDepth: Int = 256
    nonisolated private static let displayHz: Double = 60

    /// Smoothed, log-binned magnitudes in [0, 1]. Always `binCount` long.
    private(set) var magnitudes: [Float] = Array(repeating: 0, count: SpectrumAnalyzer.binCount)

    /// Newest-last rolling history of magnitude frames.
    private(set) var spectrogramHistory: [[Float]] = []

    private weak var engine: PlayerEngine?
    private var isAttached = false
    private var displayTimer: Timer?
    private var spectrogramAccumulator: Int = 0

    /// Latest FFT result, written by the audio thread and read by the
    /// display timer. The lock is uncontended in practice — the audio
    /// thread holds it for nanoseconds and the main thread reads at 60 Hz.
    nonisolated private let target = OSAllocatedUnfairLock<[Float]>(
        initialState: Array(repeating: 0, count: SpectrumAnalyzer.binCount)
    )

    init() {}

    func attach(to engine: PlayerEngine) {
        guard !isAttached else { return }
        self.engine = engine
        isAttached = true

        engine.installAnalysisTap(bufferSize: AVAudioFrameCount(Self.fftSize)) { [target] buffer, _ in
            // FFT runs on the audio thread (cheap; ~µs for a 1024-pt FFT).
            // Result is published to the lock — the display timer will
            // pick it up on the next tick.
            guard let mags = SpectrumAnalyzer.computeMagnitudes(
                from: buffer,
                fftSize: Self.fftSize,
                log2N: Self.log2N,
                binCount: Self.binCount
            ) else { return }
            target.withLock { $0 = mags }
        }

        startDisplayTimer()
    }

    func detach() {
        guard isAttached else { return }
        engine?.removeAnalysisTap()
        isAttached = false
        displayTimer?.invalidate()
        displayTimer = nil
        target.withLock { $0 = Array(repeating: 0, count: Self.binCount) }
        magnitudes = Array(repeating: 0, count: Self.binCount)
        spectrogramHistory.removeAll(keepingCapacity: false)
    }

    private func startDisplayTimer() {
        displayTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / Self.displayHz, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 0.005
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    /// Per-frame interpolation: fast attack toward higher targets, gentle
    /// decay otherwise. This makes spikes pop while letting silence fade
    /// out smoothly — the visual signature of music-spectrum displays.
    private func tick() {
        let latest = target.withLock { $0 }
        let count = magnitudes.count
        var smoothed = magnitudes
        smoothed.withUnsafeMutableBufferPointer { dst in
            latest.withUnsafeBufferPointer { src in
                for i in 0..<count {
                    let t = src[i]
                    if t > dst[i] {
                        // Fast attack: 60% of the way to the new peak per frame.
                        dst[i] += (t - dst[i]) * 0.6
                    } else {
                        // Decay: ~3% per frame at 60 Hz ≈ 0.85/sec.
                        dst[i] *= 0.97
                    }
                }
            }
        }
        magnitudes = smoothed

        // Spectrogram scrolls at 30 Hz to keep the history readable.
        spectrogramAccumulator += 1
        if spectrogramAccumulator >= 2 {
            spectrogramAccumulator = 0
            spectrogramHistory.append(smoothed)
            if spectrogramHistory.count > Self.historyDepth {
                spectrogramHistory.removeFirst(spectrogramHistory.count - Self.historyDepth)
            }
        }
    }

    // MARK: - FFT (audio thread)

    /// Pure function — runs on the audio thread, no `self` capture. Applies
    /// a Hann window, runs a real-to-complex FFT, then aggregates the linear
    /// spectrum into log-spaced bins normalized to [0, 1].
    nonisolated private static func computeMagnitudes(
        from buffer: AVAudioPCMBuffer,
        fftSize: Int,
        log2N: vDSP_Length,
        binCount: Int
    ) -> [Float]? {
        guard let channelData = buffer.floatChannelData else { return nil }
        let frameLength = Int(buffer.frameLength)
        guard frameLength >= fftSize else { return nil }

        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        var samples = [Float](repeating: 0, count: fftSize)
        let src = channelData[0]
        for i in 0..<fftSize { samples[i] = src[i] }
        vDSP_vmul(samples, 1, window, 1, &samples, 1, vDSP_Length(fftSize))

        let half = fftSize / 2
        var realp = [Float](repeating: 0, count: half)
        var imagp = [Float](repeating: 0, count: half)

        guard let setup = vDSP_create_fftsetup(log2N, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(setup) }

        var magnitudes = [Float](repeating: 0, count: half)
        realp.withUnsafeMutableBufferPointer { rp in
            imagp.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                samples.withUnsafeBufferPointer { sp in
                    sp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2N, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }

        let scale: Float = 1.0 / Float(fftSize)
        let scaled = magnitudes.map { $0 * scale }

        var output = [Float](repeating: 0, count: binCount)
        let minIdx: Float = 1
        let maxIdx: Float = Float(half - 1)
        for b in 0..<binCount {
            let t0 = Float(b) / Float(binCount)
            let t1 = Float(b + 1) / Float(binCount)
            let lo = Int(minIdx * powf(maxIdx / minIdx, t0))
            let hi = max(lo + 1, Int(minIdx * powf(maxIdx / minIdx, t1)))
            let upper = min(hi, half)
            var peak: Float = 0
            for i in lo..<upper { peak = max(peak, scaled[i]) }
            output[b] = min(1, sqrtf(peak * 8))
        }
        return output
    }
}
