import Foundation

/// A single fused sensor reading handed to the onset detector. Deliberately
/// source-agnostic: the watch fills it from HealthKit HR + CoreMotion today, and
/// a Muse EEG source can enrich it later without changing the detector contract.
public struct OnsetSignal: Sendable {
    /// Most recent heart rate in bpm, or nil if no reading has arrived yet.
    public let heartRate: Int?
    /// Normalized movement intensity, 0 (still) … 1 (vigorous).
    public let movementIntensity: Double
    /// How long the wrist has been continuously below the stillness threshold.
    public let stillSeconds: TimeInterval
    /// Most recent HRV (RMSSD, ms), or nil if no HRV source is present. Rises at
    /// sleep onset as parasympathetic tone increases.
    public let hrvRMSSD: Double?
    /// EEG-derived onset confidence (0…1) from a Muse headband, or nil if no EEG
    /// is present / signal quality is poor. The gold-standard onset signal.
    public let eegOnsetConfidence: Double?
    /// EEG says slow-wave (N3) is encroaching — the cue to wake now, before
    /// grogginess sets in.
    public let eegDeepApproaching: Bool
    /// Breathing rate (breaths/min) from the chest accelerometer, or nil. Slows
    /// and regularizes at sleep onset.
    public let breathing: Double?
    /// Blood-oxygen saturation (%), or nil. Captured for completeness — it does
    /// not shift at onset, so it isn't used for detection.
    public let spo2: Double?

    public init(heartRate: Int?, movementIntensity: Double, stillSeconds: TimeInterval,
                hrvRMSSD: Double? = nil, eegOnsetConfidence: Double? = nil,
                eegDeepApproaching: Bool = false, breathing: Double? = nil, spo2: Double? = nil) {
        self.heartRate = heartRate
        self.movementIntensity = movementIntensity
        self.stillSeconds = stillSeconds
        self.hrvRMSSD = hrvRMSSD
        self.eegOnsetConfidence = eegOnsetConfidence
        self.eegDeepApproaching = eegDeepApproaching
        self.breathing = breathing
        self.spo2 = spo2
    }
}
