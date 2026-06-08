//
//  NoiseService.swift
//  SleepBank (shared — phone and watch)
//
//  Relaxing sound for falling asleep, synthesized in real time — no audio assets.
//  White / pink / brown noise via an AVAudioEngine source node, with smooth
//  fades. Pink and brown are the sleep-friendly "colours" (energy weighted toward
//  lower frequencies, less hissy than white). Plays during a nap and fades out at
//  sleep onset (job done — saves the speaker); phone-side it can also be driven
//  manually from the Sounds screen. Each target has its own .shared instance.
//

import Foundation
import AVFoundation

enum NoiseColor: String, CaseIterable, Identifiable {
    case white, pink, brown
    var id: String { rawValue }
    var title: String {
        switch self {
        case .white: return "White"
        case .pink:  return "Pink"
        case .brown: return "Brown"
        }
    }
    var subtitle: String {
        switch self {
        case .white: return "Bright, full-spectrum hiss"
        case .pink:  return "Balanced — common for sleep"
        case .brown: return "Deep, rumbly, softest"
        }
    }
}

@Observable
class NoiseService {

    static let shared = NoiseService()

    private(set) var isPlaying = false
    var color: NoiseColor = .pink

    /// When on, the phone starts this sound automatically when a nap begins.
    /// Stored (not computed) so @Observable tracks it; persisted via didSet.
    var autoPlayDuringNap: Bool = UserDefaults.standard.bool(forKey: "noiseAutoPlay") {
        didSet { UserDefaults.standard.set(autoPlayDuringNap, forKey: "noiseAutoPlay") }
    }

    var volume: Float = 0.35 {
        didSet { applyVolume() }
    }

    /// Multiplier applied while a spoken guide is talking, so the voice sits on top.
    @ObservationIgnored private var duckLevel: Float = 1

    /// Duck (or restore) the noise under the spoken wind-down guide.
    func setDucked(_ ducked: Bool) {
        duckLevel = ducked ? 0.2 : 1
        applyVolume()
    }

    private func applyVolume() {
        engine.mainMixerNode.outputVolume = isPlaying ? volume * duckLevel : 0
    }

    /// The current audio output device (name + an SF Symbol), read live from the
    /// session route. Drives the "Output" row; the actual device picker is the
    /// AirPlay route picker on iOS (and the system Now Playing controls on watch).
    var currentOutput: (name: String, icon: String) {
        let out = AVAudioSession.sharedInstance().currentRoute.outputs.first
        let name = out?.portName ?? "Default output"
        let icon: String
        switch out?.portType {
        case .some(.builtInSpeaker): icon = "speaker.wave.2.fill"
        case .some(.headphones): icon = "headphones"
        case .some(.bluetoothA2DP), .some(.bluetoothLE), .some(.bluetoothHFP): icon = "airpods"
        case .some(.airPlay): icon = "airplayaudio"
        default: icon = "speaker.wave.2"
        }
        return (name, icon)
    }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var sourceNode: AVAudioSourceNode?
    @ObservationIgnored private var fadeTimer: Timer?

    // Realtime-safe PRNG (xorshift) and filter state for pink/brown shaping.
    @ObservationIgnored private var rng: UInt32 = 0x9E3779B9
    @ObservationIgnored private var b0: Float = 0
    @ObservationIgnored private var b1: Float = 0
    @ObservationIgnored private var b2: Float = 0
    @ObservationIgnored private var b3: Float = 0
    @ObservationIgnored private var b4: Float = 0
    @ObservationIgnored private var b5: Float = 0
    @ObservationIgnored private var b6: Float = 0
    @ObservationIgnored private var lastBrown: Float = 0

    func play(_ color: NoiseColor? = nil) {
        if let color { self.color = color }
        configureSession()
        if sourceNode == nil { installSourceNode() }
        fadeTimer?.invalidate(); fadeTimer = nil
        do {
            if !engine.isRunning { try engine.start() }
            isPlaying = true
            applyVolume()
        } catch {
            print("[Noise] engine start failed: \(error)")
        }
    }

    func stop() {
        fadeTimer?.invalidate(); fadeTimer = nil
        engine.mainMixerNode.outputVolume = 0
        engine.pause()
        isPlaying = false
        duckLevel = 1
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Ramp the volume to zero over `duration`, then stop. Used at wake.
    func fadeOut(over duration: TimeInterval = 8) {
        guard isPlaying else { return }
        fadeTimer?.invalidate()
        let steps = 40
        let interval = duration / Double(steps)
        let start = engine.mainMixerNode.outputVolume
        var step = 0
        fadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            step += 1
            self.engine.mainMixerNode.outputVolume = start * Float(steps - step) / Float(steps)
            if step >= steps { timer.invalidate(); self.stop() }
        }
    }

    // MARK: - Audio graph

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        // mixWithOthers so the spoken wind-down guide can layer over the noise.
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func installSourceNode() {
        let format = engine.outputNode.inputFormat(forBus: 0)
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList in
            guard let self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let value = self.nextSample()
                for buffer in abl {
                    let buf = buffer.mData!.assumingMemoryBound(to: Float.self)
                    buf[frame] = value
                }
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0
        sourceNode = node
    }

    /// One audio sample of the selected colour, scaled to avoid clipping.
    private func nextSample() -> Float {
        let white = whiteSample()
        switch color {
        case .white:
            return white * 0.25
        case .pink:
            // Paul Kellet's economical pink-noise filter.
            b0 = 0.99886 * b0 + white * 0.0555179
            b1 = 0.99332 * b1 + white * 0.0750759
            b2 = 0.96900 * b2 + white * 0.1538520
            b3 = 0.86650 * b3 + white * 0.3104856
            b4 = 0.55000 * b4 + white * 0.5329522
            b5 = -0.7616 * b5 - white * 0.0168980
            let pink = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362) * 0.11
            b6 = white * 0.115926
            return pink
        case .brown:
            lastBrown = (lastBrown + 0.02 * white) / 1.02
            return lastBrown * 3.5 * 0.25
        }
    }

    private func whiteSample() -> Float {
        rng ^= rng << 13
        rng ^= rng >> 17
        rng ^= rng << 5
        return (Float(rng) / Float(UInt32.max)) * 2 - 1
    }
}
