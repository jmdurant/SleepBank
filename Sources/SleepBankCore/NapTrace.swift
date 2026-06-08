import Foundation

/// Which signal(s) crossed threshold at the moment onset was declared. Lets us
/// see *why* the detector fired — essential for tuning and for labeling training
/// data by signal source.
public struct OnsetTrigger: Codable, Hashable, Sendable {
    public var heartRate: Bool
    public var hrv: Bool
    public var eeg: Bool
    public var breathing: Bool
    /// Onset was declared by a trained Core ML model rather than the heuristic.
    public var model: Bool

    public init(heartRate: Bool, hrv: Bool, eeg: Bool, breathing: Bool = false, model: Bool = false) {
        self.heartRate = heartRate
        self.hrv = hrv
        self.eeg = eeg
        self.breathing = breathing
        self.model = model
    }

    // Forgiving decoder: missing flags default to false so records written before
    // a flag existed still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        heartRate = try c.decodeIfPresent(Bool.self, forKey: .heartRate) ?? false
        hrv = try c.decodeIfPresent(Bool.self, forKey: .hrv) ?? false
        eeg = try c.decodeIfPresent(Bool.self, forKey: .eeg) ?? false
        breathing = try c.decodeIfPresent(Bool.self, forKey: .breathing) ?? false
        model = try c.decodeIfPresent(Bool.self, forKey: .model) ?? false
    }

    /// Compact label for display/logging.
    public var label: String {
        if model { return "Model" }
        if eeg { return (heartRate || hrv || breathing) ? "EEG+" : "EEG" }
        var parts: [String] = []
        if heartRate { parts.append("HR") }
        if hrv { parts.append("HRV") }
        if breathing { parts.append("Br") }
        return parts.isEmpty ? "—" : parts.joined(separator: "+")
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
    public let breathing: Double?
    public let spo2: Double?
    public let phase: String

    public init(t: TimeInterval, heartRate: Int?, hrv: Double?, movement: Double,
                stillSeconds: TimeInterval, eegOnset: Double?, eegDeep: Bool,
                breathing: Double? = nil, spo2: Double? = nil, phase: String) {
        self.t = t
        self.heartRate = heartRate
        self.hrv = hrv
        self.movement = movement
        self.stillSeconds = stillSeconds
        self.eegOnset = eegOnset
        self.eegDeep = eegDeep
        self.breathing = breathing
        self.spo2 = spo2
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
