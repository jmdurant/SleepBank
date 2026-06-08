import Foundation

/// Decides when sleep onset has occurred from a stream of fused signals.
///
/// This is the swap point for the sensor-fusion ladder: the watch-only
/// HR+immobility detector implements it now; a Muse-EEG detector (alpha→theta
/// dropout) can implement the same contract later and the engine won't change.
public protocol SleepOnsetDetector: AnyObject {
    /// Feed a new signal sampled at `time`. Returns true on the first tick at
    /// which onset is declared; false otherwise (including all later ticks).
    func update(signal: OnsetSignal, at time: Date) -> Bool
    /// The moment onset was declared, once it has been.
    var onsetTime: Date? { get }
    /// Clear all state to reuse the detector for a fresh session.
    func reset()
}
