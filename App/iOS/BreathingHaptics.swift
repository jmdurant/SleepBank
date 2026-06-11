//
//  BreathingHaptics.swift
//  SleepBank (iOS)
//
//  Core Haptics patterns for the breathing guide — the Apple-Watch-Breathe feel,
//  on the phone. Instead of one blunt tap per phase, each breath is a *continuous*
//  haptic whose intensity swells as you inhale and eases off as you exhale, with a
//  soft marker tap when you reach the hold. CHHapticEngine gives us the intensity/
//  sharpness envelopes that UIImpactFeedbackGenerator can't.
//

import Foundation
import CoreHaptics

final class BreathingHaptics {
    static let shared = BreathingHaptics()

    private var engine: CHHapticEngine?
    private var current: CHHapticPatternPlayer?
    private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    /// User-set baseline strength (0.5…2.0, default 1.0). Lets the user boost the
    /// floor so the taps are felt over real-world vibration (e.g. napping in a car).
    /// Read live from the same key the slider writes, clamped, applied to intensity.
    static let intensityKey = "hapticIntensity"
    private var intensityScale: Float {
        let v = UserDefaults.standard.object(forKey: Self.intensityKey) as? Double ?? 1.0
        return Float(min(max(v, 0.5), 2.0))
    }
    private func scaled(_ v: Float) -> Float { min(1.0, max(0.0, v * intensityScale)) }

    /// A sample tap at the current strength — for live feedback while dragging the slider.
    func previewTap() {
        guard supported else { return }
        if engine == nil { start() }
        tap(intensity: 0.7, sharpness: 0.4)
    }

    /// Spin up the haptic engine for a breathing session. Safe to call repeatedly.
    func start() {
        guard supported, engine == nil else { return }
        do {
            let engine = try CHHapticEngine()
            // Haptics only — don't touch the audio session, so the relaxing sound keeps
            // playing and nothing gets interrupted.
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = true
            // The system can reset/stop the engine (route changes, etc.) — restart it.
            engine.resetHandler = { [weak engine] in try? engine?.start() }
            engine.stoppedHandler = { _ in }
            try engine.start()
            self.engine = engine
        } catch {
            print("[BreathingHaptics] engine start failed: \(error)")
        }
    }

    func stop() {
        try? current?.stop(atTime: 0)
        current = nil
        engine?.stop()
        engine = nil
    }

    /// Play the haptic for a breathing phase, shaped to its duration.
    func play(_ phase: BreathingPacer.Phase, seconds: Double) {
        guard supported, seconds > 0 else { return }
        if engine == nil { start() }
        switch phase {
        case .inhale:
            // A strong swell: starts firm and climbs to a full, slightly sharp peak.
            ramp(seconds: seconds, intensity: (0.4, 1.0), sharpness: (0.35, 0.65))
        case .exhale:
            // A gentle, sustained release that holds a felt floor — then ends ~0.4 s
            // early, so there's a clean micro-break of stillness before the next inhale.
            ramp(seconds: max(0.5, seconds - 0.4), intensity: (0.5, 0.32), sharpness: (0.3, 0.2))
        case .hold:
            // A single soft marker tap at the top of the breath, then stillness.
            tap(intensity: 0.5, sharpness: 0.3)
        case .ready:
            break
        }
    }

    // MARK: - Patterns

    private func ramp(seconds: Double, intensity: (Float, Float), sharpness: (Float, Float)) {
        guard let engine else { return }
        let i0 = scaled(intensity.0), i1 = scaled(intensity.1)
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: i0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness.0),
            ],
            relativeTime: 0, duration: seconds)
        let intensityCurve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0, value: i0),
                .init(relativeTime: seconds, value: i1),
            ], relativeTime: 0)
        let sharpnessCurve = CHHapticParameterCurve(
            parameterID: .hapticSharpnessControl,
            controlPoints: [
                .init(relativeTime: 0, value: sharpness.0),
                .init(relativeTime: seconds, value: sharpness.1),
            ], relativeTime: 0)
        playPattern(events: [event], curves: [intensityCurve, sharpnessCurve])
    }

    private func tap(intensity: Float, sharpness: Float) {
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: scaled(intensity)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: 0)
        playPattern(events: [event], curves: [])
    }

    private func playPattern(events: [CHHapticEvent], curves: [CHHapticParameterCurve]) {
        guard let engine else { return }
        do {
            try? current?.stop(atTime: 0)   // end the previous phase's haptic cleanly
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
            current = player
        } catch {
            print("[BreathingHaptics] play failed: \(error)")
        }
    }
}
