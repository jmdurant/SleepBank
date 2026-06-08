import Foundation

/// Which signal(s) crossed threshold at the moment onset was declared. Lets us
/// see *why* the detector fired — essential for tuning and for labeling training
/// data by signal source.
public struct OnsetTrigger: Codable, Hashable, Sendable {
    public var heartRate: Bool
    public var hrv: Bool
    public var eeg: Bool

    public init(heartRate: Bool, hrv: Bool, eeg: Bool) {
        self.heartRate = heartRate
        self.hrv = hrv
        self.eeg = eeg
    }

    /// Compact label for display/logging.
    public var label: String {
        if eeg { return heartRate || hrv ? "EEG+" : "EEG" }
        if heartRate && hrv { return "HR+HRV" }
        if hrv { return "HRV" }
        if heartRate { return "HR" }
        return "—"
    }
}

/// One epoch of the nap's fused signal stream — the row a model trains on.
public struct NapEpochFeatures: Codable, Hashable, Sendable {
    public let t: TimeInterval        // seconds since session start
    public let heartRate: Int?
    public let hrv: Double?
    public let movement: Double
    public let stillSeconds: TimeInterval
    public let eegOnset: Double?
    public let eegDeep: Bool
    public let phase: String

    public init(t: TimeInterval, heartRate: Int?, hrv: Double?, movement: Double,
                stillSeconds: TimeInterval, eegOnset: Double?, eegDeep: Bool, phase: String) {
        self.t = t
        self.heartRate = heartRate
        self.hrv = hrv
        self.movement = movement
        self.stillSeconds = stillSeconds
        self.eegOnset = eegOnset
        self.eegDeep = eegDeep
        self.phase = phase
    }
}

/// The full record of one nap: our decision plus the trace that produced it.
/// Synced to the phone, compared against Apple's retrospective staging, and
/// exported as labeled training data.
public struct NapDecisionRecord: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let type: NapType
    public let start: Date
    public let end: Date
    public let onset: Date?
    public let onsetTrigger: OnsetTrigger?
    public let wakeReason: WakeReason?
    public let epochs: [NapEpochFeatures]

    public init(id: UUID, type: NapType, start: Date, end: Date, onset: Date?,
                onsetTrigger: OnsetTrigger?, wakeReason: WakeReason?, epochs: [NapEpochFeatures]) {
        self.id = id
        self.type = type
        self.start = start
        self.end = end
        self.onset = onset
        self.onsetTrigger = onsetTrigger
        self.wakeReason = wakeReason
        self.epochs = epochs
    }

    public var asleepMinutes: Int {
        guard let onset else { return 0 }
        return Int(max(0, end.timeIntervalSince(onset)) / 60)
    }

    /// Seconds from session start to detected onset (sleep latency).
    public var onsetLatency: TimeInterval? {
        onset.map { $0.timeIntervalSince(start) }
    }

    /// Whether this nap carried EEG signal (a high-quality label source).
    public var hasEEG: Bool {
        epochs.contains { $0.eegOnset != nil }
    }
}
