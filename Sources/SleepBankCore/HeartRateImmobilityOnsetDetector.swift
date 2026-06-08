import Foundation

/// Watch-and-strap sleep-onset detector. Fuses weak signals into a stronger one:
/// sustained immobility AND a cardiac sign of falling asleep — either a heart-rate
/// drop below a personal quiet-wake baseline, or a rise in HRV (RMSSD) as
/// parasympathetic tone takes over. Immobility is always required (it's what
/// keeps "lying still but awake" from reading as sleep); the cardiac side is an
/// OR so a clear HRV rise can carry a marginal HR drop, and vice-versa.
///
/// Degrades gracefully: with no HRV source (watch-only) it's exactly the
/// HR-drop + immobility detector. The HRV source today is the Polar H10 forwarded
/// from the phone. Still a v1 heuristic — personalization and EEG come later.
public final class HeartRateImmobilityOnsetDetector: SleepOnsetDetector {

    public struct Config: Sendable {
        /// Seconds of early data used to establish quiet-wake baselines.
        public var baselineWindow: TimeInterval = 120
        /// Required HR drop (bpm) below baseline to count as a cardiac onset sign.
        public var hrDropBPM: Double = 4
        /// Required HRV (RMSSD ms) rise above baseline to count as a cardiac onset sign.
        public var hrvRiseMS: Double = 10
        /// EEG onset confidence at/above which EEG alone counts as an onset sign.
        public var eegOnsetThreshold: Double = 0.6
        /// Required continuous stillness before onset can be declared.
        public var requiredStillSeconds: TimeInterval = 90
        /// Both conditions must hold continuously this long (debounce).
        public var holdSeconds: TimeInterval = 20
        /// Window over which "recent" HR/HRV are averaged.
        public var smoothingWindow: TimeInterval = 20
        public init() {}
    }

    private let config: Config
    private var startTime: Date?
    private var hrSamples: [(t: Date, v: Double)] = []
    private var hrvSamples: [(t: Date, v: Double)] = []
    private var hrBaseline: Double?
    private var hrvBaseline: Double?
    private var candidateSince: Date?
    public private(set) var onsetTime: Date?

    public init(config: Config = Config()) {
        self.config = config
    }

    public func reset() {
        startTime = nil
        hrSamples.removeAll()
        hrvSamples.removeAll()
        hrBaseline = nil
        hrvBaseline = nil
        candidateSince = nil
        onsetTime = nil
    }

    public func update(signal: OnsetSignal, at time: Date) -> Bool {
        guard onsetTime == nil else { return false }   // declare once
        if startTime == nil { startTime = time }
        guard let start = startTime else { return false }

        collect(signal.heartRate.map(Double.init), into: &hrSamples, at: time)
        collect(signal.hrvRMSSD, into: &hrvSamples, at: time)

        // Establish baselines once the early window has elapsed.
        if time.timeIntervalSince(start) >= config.baselineWindow {
            if hrBaseline == nil { hrBaseline = baseline(of: hrSamples, start: start) }
            if hrvBaseline == nil { hrvBaseline = baseline(of: hrvSamples, start: start) }
        }

        // Cardiac onset signs — each only evaluable when its baseline + a recent
        // reading exist. Either one suffices.
        let hrDropped: Bool = {
            guard let base = hrBaseline, let recent = recentAverage(hrSamples, at: time) else { return false }
            return recent <= base - config.hrDropBPM
        }()
        let hrvRose: Bool = {
            guard let base = hrvBaseline, let recent = recentAverage(hrvSamples, at: time) else { return false }
            return recent >= base + config.hrvRiseMS
        }()
        // EEG is the gold-standard onset signal — no baseline needed; the phone
        // only forwards it when contact quality is good.
        let eegOnset = (signal.eegOnsetConfidence ?? 0) >= config.eegOnsetThreshold
        let cardiacSign = hrDropped || hrvRose || eegOnset
        let stillEnough = signal.stillSeconds >= config.requiredStillSeconds

        if cardiacSign && stillEnough {
            if candidateSince == nil { candidateSince = time }
            if let since = candidateSince, time.timeIntervalSince(since) >= config.holdSeconds {
                onsetTime = time
                return true
            }
        } else {
            candidateSince = nil
        }
        return false
    }

    // MARK: - Helpers

    private func collect(_ value: Double?, into buffer: inout [(t: Date, v: Double)], at time: Date) {
        guard let value, value > 0 else { return }
        buffer.append((time, value))
        let cutoff = time.addingTimeInterval(-300)   // keep ~5 min
        while let first = buffer.first, first.t < cutoff { buffer.removeFirst() }
    }

    private func baseline(of buffer: [(t: Date, v: Double)], start: Date) -> Double? {
        let windowEnd = start.addingTimeInterval(config.baselineWindow)
        let early = buffer.filter { $0.t <= windowEnd }
        guard !early.isEmpty else { return nil }
        return early.map(\.v).reduce(0, +) / Double(early.count)
    }

    private func recentAverage(_ buffer: [(t: Date, v: Double)], at time: Date) -> Double? {
        let recent = buffer.filter { $0.t >= time.addingTimeInterval(-config.smoothingWindow) }
        guard !recent.isEmpty else { return nil }
        return recent.map(\.v).reduce(0, +) / Double(recent.count)
    }
}
