import Foundation

/// The "energy ring" model — a deliberately *qualitative* estimate of how much
/// alertness boost your most recent nap is still giving you right now.
///
/// This is illustrative, not a measurement. The evidence (see
/// `docs/NAP_BENEFIT_EVIDENCE.md` §2) is that a short nap restores *subjective*
/// alertness that fades over ~1–3 hours, and that a cycle nap does more (real
/// N3/REM). So the ring fills on waking and empties over the nap's benefit
/// window — the quiet draining *is* the honest story (alertness is transient).
/// There is no sleep-debt accounting here: a nap is a top-up, not a ledger entry.
public struct AlertnessCharge: Equatable, Sendable {
    /// 0…1 — how "charged" the last nap leaves you at the queried time.
    public let level: Double
    /// Whole minutes until the boost has essentially faded (0 when none active).
    public let minutesRemaining: Int
    /// The nap type that produced the boost, if one is still active.
    public let source: NapType?

    public init(level: Double, minutesRemaining: Int, source: NapType?) {
        self.level = level
        self.minutesRemaining = minutesRemaining
        self.source = source
    }

    /// No active boost — the resting/"ready to nap" state.
    public static let empty = AlertnessCharge(level: 0, minutesRemaining: 0, source: nil)

    /// How long each nap type's alertness boost takes to fade. Anchored to the
    /// benefit-duration evidence: a brief nap's benefit lasts ~125 min
    /// (Brooks & Lack 2006, 20-min nap), a full cycle's restorative effect longer.
    static func benefitWindow(for type: NapType) -> TimeInterval {
        switch type {
        case .power: return 125 * 60
        case .cycle: return 180 * 60
        }
    }

    /// Peak charge right after waking. A power nap is a clean top-up (not "fully
    /// rested"); a cycle nap, which actually discharges some sleep pressure, peaks
    /// higher.
    static func peak(for type: NapType) -> Double {
        switch type {
        case .power: return 0.85
        case .cycle: return 1.0
        }
    }

    /// The current charge given the most recent nap. Linear fade from peak (at the
    /// moment of waking) to zero (at the end of the benefit window). The peak is
    /// scaled by how much the user actually slept versus the nap's target, so a
    /// brief micro-sleep gives a smaller boost than a full nap, and a nap where
    /// onset was never detected gives none.
    public static func current(now: Date, lastNap: NapRecord?) -> AlertnessCharge {
        guard let nap = lastNap, let onset = nap.onset else { return .empty }

        let window = benefitWindow(for: nap.type)
        let elapsed = now.timeIntervalSince(nap.end)
        guard elapsed >= 0, elapsed < window else { return .empty }

        let asleep = nap.end.timeIntervalSince(onset)
        let fullness = min(max(asleep / nap.type.targetWakeAfterOnset, 0), 1)
        let remainingFraction = 1 - (elapsed / window)
        let level = peak(for: nap.type) * fullness * remainingFraction

        // Negligible boost reads as "ready to nap," not a sliver of ring.
        guard level >= 0.01 else { return .empty }

        return AlertnessCharge(
            level: level,
            minutesRemaining: Int((window - elapsed) / 60),
            source: nap.type
        )
    }
}
