import Foundation

/// Detects descent toward slow-wave (N3) sleep from non-EEG signals, so the smart
/// alarm can wake the sleeper *before* deep sleep even without a Muse headband.
///
/// Deep sleep's signature vs. light sleep: heart rate falls *further* below the
/// just-fell-asleep level, the body goes completely still, and breathing slows
/// and regularizes. This is the symmetric partner to the awakening detector.
///
/// Deliberately conservative — a false positive wakes the napper too early and
/// cuts the nap short (unlike the awakening detector, where a miss is harmless).
/// So it requires *multiple* signs, sustained, and never fires in the first
/// several minutes after onset. Thresholds are flagged for n=1 calibration.
public final class DeepeningDetector {

    public struct Config: Sendable {
        /// Never fire before this long after onset (N3 doesn't appear instantly).
        public var minSecondsAfterOnset: TimeInterval = 480     // 8 min
        /// HR must fall this far below the just-after-onset reference.
        public var hrFurtherDropBPM: Double = 3
        /// Immobility deeper/longer than the onset stillness gate.
        public var deepStillSeconds: TimeInterval = 120
        /// The combined signature must hold this long.
        public var holdSeconds: TimeInterval = 60
        /// Window after onset used to establish the sleeping-HR reference.
        public var referenceWindow: TimeInterval = 120
        public init() {}
    }

    private let config: Config
    private var referenceSamples: [Double] = []
    private var postOnsetHR: Double?
    private var deepeningSince: Date?
    public private(set) var deepeningDetected = false

    public init(config: Config = Config()) {
        self.config = config
    }

    public func reset() {
        referenceSamples.removeAll()
        postOnsetHR = nil
        deepeningSince = nil
        deepeningDetected = false
    }

    /// Feed a post-onset signal. Returns true once deepening is declared.
    public func update(signal: OnsetSignal, onset: Date, at time: Date) -> Bool {
        guard !deepeningDetected else { return false }
        let sinceOnset = time.timeIntervalSince(onset)

        // Establish the just-after-onset HR reference (light-sleep level).
        if let hr = signal.heartRate, hr > 0, sinceOnset <= config.referenceWindow {
            referenceSamples.append(Double(hr))
        }
        if postOnsetHR == nil, sinceOnset > config.referenceWindow, !referenceSamples.isEmpty {
            postOnsetHR = referenceSamples.reduce(0, +) / Double(referenceSamples.count)
        }

        guard sinceOnset >= config.minSecondsAfterOnset, let ref = postOnsetHR else { return false }

        // Signature of descending into N3: HR further down AND deeply still.
        let hrFurther: Bool = {
            guard let hr = signal.heartRate, hr > 0 else { return false }
            return Double(hr) <= ref - config.hrFurtherDropBPM
        }()
        let deepStill = signal.stillSeconds >= config.deepStillSeconds
        let signature = hrFurther && deepStill

        if signature {
            if deepeningSince == nil { deepeningSince = time }
            if let s = deepeningSince, time.timeIntervalSince(s) >= config.holdSeconds {
                deepeningDetected = true
                return true
            }
        } else {
            deepeningSince = nil
        }
        return false
    }
}
