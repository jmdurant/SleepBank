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
    /// The sleeper woke on their own before the alarm — end gracefully, no alarm.
    public let naturallyWoke: Bool
}

/// Drives a single nap from start to wake. Time is injected via `tick(now:…)`
/// so the whole thing is deterministic and unit-testable without a clock.
public final class NapEngine {

    public let type: NapType
    public let sessionStart: Date
    private let detector: SleepOnsetDetector
    private let awakening: AwakeningDetector
    private let deepening: DeepeningDetector

    private var onsetTime: Date?
    private var wakeTarget: Date?
    private var alarming = false
    private var naturallyWoke = false
    private var finished = false

    public init(type: NapType, sessionStart: Date, detector: SleepOnsetDetector,
                awakeningDetector: AwakeningDetector = AwakeningDetector(),
                deepeningDetector: DeepeningDetector = DeepeningDetector()) {
        self.type = type
        self.sessionStart = sessionStart
        self.detector = detector
        self.awakening = awakeningDetector
        self.deepening = deepeningDetector
    }

    /// Absolute latest the alarm will fire, regardless of onset.
    public var ceiling: Date {
        sessionStart.addingTimeInterval(type.maxSessionDuration)
    }

    public func tick(now: Date, signal: OnsetSignal) -> NapTick {
        if finished {
            return NapTick(phase: .finished, onsetTime: onsetTime, wakeTarget: wakeTarget,
                           isAlarming: false, wakeReason: .manual, timeUntilWake: nil, naturallyWoke: false)
        }

        // Onset detection (only until we have it).
        if onsetTime == nil, detector.update(signal: signal, at: now) {
            let onset = detector.onsetTime ?? now
            onsetTime = onset
            // Wake at onset + target, but never past the safety ceiling.
            wakeTarget = min(onset.addingTimeInterval(type.targetWakeAfterOnset), ceiling)
        }

        // Post-onset state detectors — only before any alarm.
        var physiologicalDeepening = false
        if let onset = onsetTime, !alarming, !naturallyWoke {
            if awakening.update(signal: signal, at: now) { naturallyWoke = true }
            physiologicalDeepening = deepening.update(signal: signal, onset: onset, at: now)
        }

        // Decide the outcome.
        var reason: WakeReason? = nil
        var fireAlarm = false
        if naturallyWoke {
            reason = .spontaneous                 // woke on their own — no alarm
        } else if let wt = wakeTarget, now >= wt {
            reason = (wt >= ceiling) ? .ceiling : .reachedTarget; fireAlarm = true
        } else if now >= ceiling {
            reason = .ceiling; fireAlarm = true
        } else if onsetTime != nil && (signal.eegDeepApproaching || physiologicalDeepening) {
            // Deep sleep is approaching (EEG delta, or HR-falling-further + deeply
            // still) — wake now, before N3, to dodge grogginess.
            reason = .deepening; fireAlarm = true
        }
        if fireAlarm { alarming = true }

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
                       isAlarming: alarming, wakeReason: reason,
                       timeUntilWake: until, naturallyWoke: naturallyWoke)
    }

    /// End the session (manual stop or after the user clears the alarm).
    public func finish() {
        finished = true
        alarming = false
    }
}
