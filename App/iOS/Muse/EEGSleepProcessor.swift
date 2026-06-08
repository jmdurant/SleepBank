//
//  EEGSleepProcessor.swift
//  SleepBank
//
//  Harvested from SexKit's EEGProcessor. The signal-processing core — vDSP real
//  FFT over 256-sample (1 s) Hanning-windowed frames at 256 Hz, per-channel band
//  powers, artifact rejection — is kept intact because it is domain-neutral and
//  well-built. What's replaced is the *derived* layer: instead of arousal/flow
//  metrics, we compute the two events a nap cares about, which a frontal montage
//  (AF7/AF8 + TP9/TP10) can actually see:
//
//    • Sleep ONSET — alpha attenuation + theta emergence (the N1 signature).
//    • Deep-sleep APPROACH — rising delta (the "wake now" trigger).
//
//  Plus a spindle-band (sigma, ~12–15 Hz) power as an N2 hint and a crude
//  per-channel contact-quality gate, since EEG-derived state should only be
//  trusted when the electrodes are actually on the skin.
//

import Foundation
import Accelerate

@Observable
class EEGSleepProcessor {

    struct BandPowers {
        var delta: Float = 0     // 1-4 Hz  — deep sleep (N3)
        var theta: Float = 0     // 4-8 Hz  — drowsy / N1 onset
        var alpha: Float = 0     // 8-12 Hz — relaxed wake, eyes closed
        var sigma: Float = 0     // 12-15 Hz — sleep spindles (N2)
        var beta: Float = 0      // 15-30 Hz — alert
        var gamma: Float = 0     // 30-44 Hz
    }

    // Per-channel and averaged relative powers.
    var tp9Powers = BandPowers()
    var af7Powers = BandPowers()
    var af8Powers = BandPowers()
    var tp10Powers = BandPowers()
    var avgPowers = BandPowers()

    // MARK: - Sleep-derived metrics

    /// 0…1 confidence that the EEG looks like sleep onset (alpha gone, theta up).
    var onsetIndex: Float = 0
    /// True once onset signature has held briefly.
    var onsetDetected = false
    /// 0…1 — relative delta; high and rising means N3 is encroaching.
    var deltaDominance: Float = 0
    /// True when delta suggests deep sleep is approaching — the wake trigger.
    var deepSleepApproaching = false
    /// Spindle-band power — a hint that the sleeper has consolidated into N2.
    var spindlePower: Float = 0

    /// Per-channel contact quality, 0 (no contact) … 1 (good contact).
    var channelQuality: [Float] = [0, 0, 0, 0]
    /// Whether enough channels have contact to trust EEG-derived state.
    var hasGoodSignal = false
    /// Live raw per-channel diagnostics (12-bit ADC units) for calibration.
    var channelRange: [Float] = [0, 0, 0, 0]
    var channelMean: [Float] = [0, 0, 0, 0]
    /// Recent raw samples from AF7 (left frontal) for the live waveform display.
    var traceSamples: [Float] = []
    private let traceLength = 512   // ~2 s at 256 Hz

    // MARK: - Configuration

    let sampleRate: Float = 256
    let fftSize = 256
    let channels = 4
    private let blinkThreshold: Float = 800   // frontal amplitude spike = blink
    private let jawClenchThreshold: Float = 600 // temporal spike = jaw clench
    private let flatlineThreshold: Float = 5    // range below this = no skin contact

    // MARK: - Internal state

    private var channelBuffers: [[Float]] = [[], [], [], []]
    private var fftSetup: FFTSetup?
    private var log2n: vDSP_Length = 0
    private var window: [Float] = []
    private var cleanHistory: [[Bool]] = [[], [], [], []]
    private let qualityWindow = 8

    // Quiet-wake baseline (captured shortly after a clean signal appears).
    private var alphaBaseline: Float = 0
    private var baselineCaptured = false
    private var deltaHistory: [Float] = []
    private var onsetHoldFrames = 0

    init() {
        log2n = vDSP_Length(log2(Float(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        if let setup = fftSetup { vDSP_destroy_fftsetup(setup) }
    }

    func reset() {
        channelBuffers = [[], [], [], []]
        cleanHistory = [[], [], [], []]
        channelRange = [0, 0, 0, 0]
        channelMean = [0, 0, 0, 0]
        traceSamples = []
        alphaBaseline = 0
        baselineCaptured = false
        deltaHistory.removeAll()
        onsetHoldFrames = 0
        onsetIndex = 0
        onsetDetected = false
        deepSleepApproaching = false
    }

    // MARK: - Feed raw EEG

    /// Feed raw samples for one channel (Muse delivers 12 per packet per channel).
    func feedSamples(channel: Int, samples: [Float]) {
        guard channel < channels else { return }
        channelBuffers[channel].append(contentsOf: samples)
        let maxSamples = fftSize * 2
        if channelBuffers[channel].count > maxSamples {
            channelBuffers[channel].removeFirst(channelBuffers[channel].count - maxSamples)
        }
        // AF7 (channel 1) feeds the live waveform trace.
        if channel == 1 {
            traceSamples.append(contentsOf: samples)
            if traceSamples.count > traceLength {
                traceSamples.removeFirst(traceSamples.count - traceLength)
            }
        }
        // Channel 0 filling up triggers a full multi-channel update.
        if channel == 0 && channelBuffers[0].count >= fftSize {
            processAllChannels()
        }
    }

    // MARK: - FFT pipeline

    private func processAllChannels() {
        for ch in 0..<channels {
            guard channelBuffers[ch].count >= fftSize else { continue }
            let samples = Array(channelBuffers[ch].suffix(fftSize))

            let (clean, contact) = assessQuality(samples, channel: ch)
            recordQuality(channel: ch, contact: contact)   // contact, not cleanliness
            guard clean && contact else { continue }       // skip artifacted/no-contact frames for the FFT

            var windowed = [Float](repeating: 0, count: fftSize)
            vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))
            let powers = computeFFT(windowed)

            switch ch {
            case 0: tp9Powers = powers
            case 1: af7Powers = powers
            case 2: af8Powers = powers
            case 3: tp10Powers = powers
            default: break
            }
        }

        computeAveragePowers()
        updateSignalQuality()

        guard hasGoodSignal else { return }

        if !baselineCaptured && avgPowers.alpha > 0.01 {
            alphaBaseline = avgPowers.alpha
            baselineCaptured = true
        }
        computeSleepMetrics()
    }

    private func computeFFT(_ samples: [Float]) -> BandPowers {
        let n = fftSize
        let halfN = n / 2
        guard let setup = fftSetup else { return BandPowers() }

        var realPart = [Float](repeating: 0, count: halfN)
        var imagPart = [Float](repeating: 0, count: halfN)
        for i in 0..<halfN {
            realPart[i] = samples[i * 2]
            imagPart[i] = i * 2 + 1 < n ? samples[i * 2 + 1] : 0
        }

        var magnitudes = [Float](repeating: 0, count: halfN)
        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfN))
            }
        }

        // Bin resolution = 256/256 = 1 Hz, so bin index ≈ frequency in Hz.
        let delta = sumBins(magnitudes, 1, 4)
        let theta = sumBins(magnitudes, 4, 8)
        let alpha = sumBins(magnitudes, 8, 12)
        let sigma = sumBins(magnitudes, 12, 15)
        let beta = sumBins(magnitudes, 15, 30)
        let gamma = sumBins(magnitudes, 30, 44)
        let total = delta + theta + alpha + sigma + beta + gamma
        guard total > 0 else { return BandPowers() }
        return BandPowers(delta: delta / total, theta: theta / total, alpha: alpha / total,
                          sigma: sigma / total, beta: beta / total, gamma: gamma / total)
    }

    private func sumBins(_ magnitudes: [Float], _ from: Int, _ to: Int) -> Float {
        let start = max(0, min(from, magnitudes.count))
        let end = max(0, min(to, magnitudes.count))
        guard start < end else { return 0 }
        return magnitudes[start..<end].reduce(0, +)
    }

    // MARK: - Quality

    /// Returns (isClean, hasContact) for a frame.
    /// - contact: the electrode is on skin producing real signal — mean sits away
    ///   from the ADC rails and the window isn't flat. A blink is a large
    ///   deflection but *confirms* contact, so it counts as contact.
    /// - clean: free of large transient artifact (blink/jaw). Used only to gate
    ///   which frames feed the FFT, NOT whether we have contact.
    private func assessQuality(_ samples: [Float], channel: Int) -> (clean: Bool, contact: Bool) {
        let maxV = samples.max() ?? 0
        let minV = samples.min() ?? 0
        let range = maxV - minV
        let mean = samples.reduce(0, +) / Float(samples.count)

        channelRange[channel] = range   // live diagnostics for calibration
        channelMean[channel] = mean

        // Contact: not flatlined, and DC not pinned to a rail (12-bit, 0…4095).
        let alive = range > flatlineThreshold
        let offRails = mean > 200 && mean < 3895
        let contact = alive && offRails

        let threshold = (channel == 1 || channel == 2) ? blinkThreshold : jawClenchThreshold
        let clean = range < threshold
        return (clean, contact)
    }

    private func recordQuality(channel: Int, contact: Bool) {
        cleanHistory[channel].append(contact)
        if cleanHistory[channel].count > qualityWindow {
            cleanHistory[channel].removeFirst()
        }
    }

    private func updateSignalQuality() {
        for ch in 0..<channels {
            let h = cleanHistory[ch]
            channelQuality[ch] = h.isEmpty ? 0 : Float(h.filter { $0 }.count) / Float(h.count)
        }
        // Trust EEG state when the two frontal channels have steady contact.
        hasGoodSignal = channelQuality[1] > 0.5 && channelQuality[2] > 0.5
    }

    private func computeAveragePowers() {
        func avg(_ k: (BandPowers) -> Float) -> Float {
            (k(tp9Powers) + k(af7Powers) + k(af8Powers) + k(tp10Powers)) / 4
        }
        avgPowers = BandPowers(
            delta: avg(\.delta), theta: avg(\.theta), alpha: avg(\.alpha),
            sigma: avg(\.sigma), beta: avg(\.beta), gamma: avg(\.gamma)
        )
    }

    // MARK: - Sleep metrics

    private func computeSleepMetrics() {
        // ONSET: alpha attenuated vs quiet-wake baseline AND theta now exceeds alpha.
        let alphaRatio = alphaBaseline > 0.01 ? avgPowers.alpha / alphaBaseline : 1
        let alphaAttenuated = max(0, min(1, (1 - alphaRatio) / 0.6))   // full credit by 60% drop
        let thetaOverAlpha = avgPowers.alpha > 0.01 ? avgPowers.theta / avgPowers.alpha : 0
        let thetaEmergent = max(0, min(1, (thetaOverAlpha - 1) / 1.0))  // theta passing alpha
        onsetIndex = min(1, 0.6 * alphaAttenuated + 0.4 * thetaEmergent)

        if onsetIndex > 0.6 {
            onsetHoldFrames += 1
        } else {
            onsetHoldFrames = max(0, onsetHoldFrames - 1)
        }
        onsetDetected = onsetHoldFrames >= 3   // held ~3 s

        // DEEP SLEEP APPROACH: relative delta rising.
        deltaDominance = avgPowers.delta
        deltaHistory.append(avgPowers.delta)
        if deltaHistory.count > 10 { deltaHistory.removeFirst() }
        let rising = (deltaHistory.last ?? 0) > (deltaHistory.first ?? 0) + 0.05
        deepSleepApproaching = avgPowers.delta > 0.35 && rising

        // N2 hint.
        spindlePower = avgPowers.sigma
    }
}
