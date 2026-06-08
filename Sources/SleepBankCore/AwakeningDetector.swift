import Foundation

/// Detects spontaneous awakening during a nap — the inverse of onset. Runs only
/// after sleep onset. Where onset is "still AND a sleep sign," waking is "moving
/// (or a clear wake sign) sustained." Movement is the workhorse (you almost
/// always move when you wake), corroborated by HR returning toward wake levels,
/// breathing speeding up, and EEG desynchronizing (alpha returning).
///
/// Debounced so a brief position change or micro-arousal doesn't end the nap.
public final class AwakeningDetector {

    public struct Config: Sendable {
        /// Movement above this is "moving" (mirror of the onset stillness gate).
        public var movementThreshold: Double = 0.12
        /// Sustained movement this long ⇒ awake.
        public var sustainedMovementSeconds: TimeInterval = 45
        /// HR rise (bpm) above the sleeping low that, while moving, counts as waking.
        public var hrRiseBPM: Double = 5
        /// Sustained HR-rise-with-movement this long ⇒ awake.
        public var hrRiseSeconds: TimeInterval = 20
        /// EEG onset confidence below this (alpha back / desynchronized) ⇒ awake.
        public var eegAwakeBelow: Double = 0.2
        public var eegAwakeSeconds: TimeInterval = 15
        public init() {}
    }

    private let config: Config
    private var movingSince: Date?
    private var hrRiseSince: Date?
    private var eegAwakeSince: Date?
    private var sleepHRLow: Double?     // lowest HR seen during this sleep
    public private(set) var awakened = false

    public init(config: Config = Config()) {
        self.config = config
    }

    public func reset() {
        movingSince = nil
        hrRiseSince = nil
        eegAwakeSince = nil
        sleepHRLow = nil
        awakened = false
    }

    /// Feed a post-onset signal. Returns true on the first tick awakening is declared.
    public func update(signal: OnsetSignal, at time: Date) -> Bool {
        guard !awakened else { return false }
        let moving = signal.movementIntensity > config.movementThreshold

        // Track the sleeping HR low so we can spot a rise back toward wake.
        if let hr = signal.heartRate, hr > 0 {
            sleepHRLow = sleepHRLow.map { min($0, Double(hr)) } ?? Double(hr)
        }

        // 1) Sustained gross movement.
        if moving {
            if movingSince == nil { movingSince = time }
            if let s = movingSince, time.timeIntervalSince(s) >= config.sustainedMovementSeconds {
                awakened = true; return true
            }
        } else {
            movingSince = nil
        }

        // 2) HR risen back toward wake while moving.
        if moving, let hr = signal.heartRate, let low = sleepHRLow, Double(hr) >= low + config.hrRiseBPM {
            if hrRiseSince == nil { hrRiseSince = time }
            if let s = hrRiseSince, time.timeIntervalSince(s) >= config.hrRiseSeconds {
                awakened = true; return true
            }
        } else {
            hrRiseSince = nil
        }

        // 3) EEG desynchronized (alpha back) — the gold-standard wake sign.
        if let eeg = signal.eegOnsetConfidence, eeg < config.eegAwakeBelow {
            if eegAwakeSince == nil { eegAwakeSince = time }
            if let s = eegAwakeSince, time.timeIntervalSince(s) >= config.eegAwakeSeconds {
                awakened = true; return true
            }
        } else {
            eegAwakeSince = nil
        }

        return false
    }
}
