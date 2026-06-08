import Foundation

/// Where a nap session is in its lifecycle. Drives what the UI shows and when
/// the alarm arms.
public enum NapPhase: String, Sendable {
    /// Session started; the user is settling and we are gathering a baseline.
    case settling
    /// The user is still; we are actively watching for sleep onset.
    case monitoring
    /// Onset detected; the wake timer is armed.
    case asleep
    /// The alarm is firing.
    case waking
    /// Session ended.
    case finished
}

/// Why the alarm went off — useful for logging and for honest UI copy.
public enum WakeReason: String, Codable, Sendable {
    /// Reached the onset-relative target (the good case).
    case reachedTarget
    /// Hit the absolute session ceiling, e.g. onset was never detected.
    case ceiling
    /// EEG showed deep sleep (N3) encroaching — woke early to avoid grogginess.
    case deepening
    /// The sleeper woke on their own before the alarm (detected awakening).
    case spontaneous
    /// The user ended the session manually.
    case manual
}
