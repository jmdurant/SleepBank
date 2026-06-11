//
//  BreathingPacer.swift
//  SleepBank (shared — phone and watch)
//
//  A precisely-timed 4-7-8 breathing pacer driven by *haptics* (gentle taps at each
//  phase change) rather than a robotic voice — so it works with your eyes closed
//  during a nap, and drives the Wind Down breathing circle when your eyes are open.
//  Exact timers, so the cadence never drifts the way TTS does.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WatchKit)
import WatchKit
#endif

@Observable
final class BreathingPacer {
    static let shared = BreathingPacer()

    enum Phase: Equatable {
        case ready, inhale, hold, exhale
        var label: String {
            switch self {
            case .ready:  return ""
            case .inhale: return "Breathe in"
            case .hold:   return "Hold"
            case .exhale: return "Breathe out"
            }
        }
        var seconds: Double {
            switch self {
            case .ready:  return 0
            case .inhale: return 4
            case .hold:   return 7
            case .exhale: return 8
            }
        }
        /// Where the breathing circle should be (0…1) during this phase.
        var targetScale: Double {
            switch self {
            case .ready:  return 0.5
            case .inhale: return 1.0
            case .hold:   return 1.0
            case .exhale: return 0.45
            }
        }
    }

    private(set) var phase: Phase = .ready
    private(set) var isRunning = false
    private(set) var cycle = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Run `cycles` rounds of 4-7-8. Use a small count for a focused Wind Down session,
    /// a large one for a nap (it's stopped at sleep onset).
    func start(cycles: Int = 8) {
        stop()
        isRunning = true
        #if os(iOS)
        BreathingHaptics.shared.start()
        #endif
        task = Task { @MainActor in
            for c in 1...max(1, cycles) {
                if Task.isCancelled { break }
                cycle = c
                await run(.inhale); await run(.hold); await run(.exhale)
            }
            if !Task.isCancelled { phase = .ready; isRunning = false }
        }
    }

    func stop() {
        task?.cancel(); task = nil
        isRunning = false; phase = .ready; cycle = 0
        #if os(iOS)
        BreathingHaptics.shared.stop()
        #endif
    }

    @MainActor private func run(_ p: Phase) async {
        if Task.isCancelled { return }
        phase = p
        haptic(p)
        try? await Task.sleep(for: .seconds(p.seconds))
    }

    private func haptic(_ p: Phase) {
        #if os(iOS)
        // A swelling Core Haptics pattern shaped to the phase — the Apple-Watch-Breathe
        // feel (rises on the inhale, releases on the exhale), not one blunt tap.
        BreathingHaptics.shared.play(p, seconds: p.seconds)
        #elseif canImport(WatchKit)
        WKInterfaceDevice.current().play(p == .inhale ? .start : (p == .exhale ? .stop : .click))
        #endif
    }
}
