import Foundation

/// The result of advancing the nap state machine by one tick.
public struct NapTick: Sendable {
    public let phase: NapPhase
    public let onsetTime: Date?
    /// The armed wake time, once onset is known.
    public let wakeTarget: Date?
    /// True whenever the alarm should be sounding. Idempotent: stays true every
    /// tick while in `.waking`, so the caller can start the alarm once and trust
    /// the flag to keep it going.
    public let isAlarming: Bool
    public let wakeReason: WakeReason?
    /// Seconds until wake. Counts down to the wake target once onset is known,
    /// otherwise counts down to the session ceiling.
    public let timeUntilWake: TimeInterval?
}

/// Drives a single nap from start to wake. Time is injected via `tick(now:…)`
/// so the whole thing is deterministic and unit-testable without a clock.
public final class NapEngine {

    public let type: NapType
    public let sessionStart: Date
    private let detector: SleepOnsetDetector

    private var onsetTime: Date?
    private var wakeTarget: Date?
    private var alarming = false
    private var finished = false

    public init(type: NapType, sessionStart: Date, detector: SleepOnsetDetector) {
        self.type = type
        self.sessionStart = sessionStart
        self.detector = detector
    }

    /// Absolute latest the alarm will fire, regardless of onset.
    public var ceiling: Date {
        sessionStart.addingTimeInterval(type.maxSessionDuration)
    }

    public func tick(now: Date, signal: OnsetSignal) -> NapTick {
        if finished {
            return NapTick(phase: .finished, onsetTime: onsetTime, wakeTarget: wakeTarget,
                           isAlarming: false, wakeReason: .manual, timeUntilWake: nil)
        }

        // Onset detection (only until we have it).
        if onsetTime == nil, detector.update(signal: signal, at: now) {
            let onset = detector.onsetTime ?? now
            onsetTime = onset
            // Wake at onset + target, but never past the safety ceiling.
            wakeTarget = min(onset.addingTimeInterval(type.targetWakeAfterOnset), ceiling)
        }

        // Should the alarm fire?
        var reason: WakeReason? = nil
        if let wt = wakeTarget, now >= wt {
            reason = (wt >= ceiling) ? .ceiling : .reachedTarget
        } else if now >= ceiling {
            reason = .ceiling
        } else if onsetTime != nil && signal.eegDeepApproaching {
            // EEG sees N3 coming before the timer — wake early to dodge inertia.
            reason = .deepening
        }
        if reason != nil { alarming = true }

        // Phase.
        let phase: NapPhase
        if alarming {
            phase = .waking
        } else if onsetTime != nil {
            phase = .asleep
        } else if signal.stillSeconds >= 30 {
            phase = .monitoring
        } else {
            phase = .settling
        }

        // Countdown.
        let until: TimeInterval?
        if let wt = wakeTarget {
            until = max(0, wt.timeIntervalSince(now))
        } else {
            until = max(0, ceiling.timeIntervalSince(now))
        }

        return NapTick(phase: phase, onsetTime: onsetTime, wakeTarget: wakeTarget,
                       isAlarming: alarming, wakeReason: alarming ? reason : nil,
                       timeUntilWake: until)
    }

    /// End the session (manual stop or after the user clears the alarm).
    public func finish() {
        finished = true
        alarming = false
    }
}
