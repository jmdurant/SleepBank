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

    public init(heartRate: Int?, movementIntensity: Double, stillSeconds: TimeInterval,
                hrvRMSSD: Double? = nil) {
        self.heartRate = heartRate
        self.movementIntensity = movementIntensity
        self.stillSeconds = stillSeconds
        self.hrvRMSSD = hrvRMSSD
    }
}
