import Foundation

/// The kinds of nap the user can choose, each with its own wake strategy.
///
/// The clinical intent:
/// - `.power` — wake in N1/early-N2, before slow-wave (N3) consolidates around
///   the 20–30 min mark, to avoid sleep inertia ("grogginess").
/// - `.cycle` — ride one full sleep cycle (~90 min) and wake out of light sleep
///   at the end of the cycle.
///
/// Times are measured from *sleep onset*, not from the clock, with an absolute
/// ceiling from session start so the alarm still fires if onset is never detected.
public enum NapType: String, CaseIterable, Codable, Sendable {
    case power
    case cycle

    public var title: String {
        switch self {
        case .power: return "Power Nap"
        case .cycle: return "Cycle Nap"
        }
    }

    public var subtitle: String {
        switch self {
        case .power: return "~20 min · wake before deep sleep"
        case .cycle: return "~90 min · one full cycle"
        }
    }

    /// Target interval after sleep onset at which to wake.
    public var targetWakeAfterOnset: TimeInterval {
        switch self {
        case .power: return 18 * 60
        case .cycle: return 90 * 60
        }
    }

    /// Absolute ceiling from session start. The alarm fires by this time no
    /// matter what — a safety net for when onset detection misses entirely.
    public var maxSessionDuration: TimeInterval {
        switch self {
        case .power: return 30 * 60
        case .cycle: return 110 * 60
        }
    }
}
