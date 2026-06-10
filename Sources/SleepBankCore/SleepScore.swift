import Foundation

/// Our own 0–100 sleep score, reverse-engineered to track **Apple's** Sleep Score so
/// the number feels familiar (Apple computes theirs in the Health app and doesn't
/// expose it — HealthKit gives the raw samples, not the score — so we rebuild an
/// equivalent from the same ingredients). It drives where today's alertness curve
/// starts.
///
/// Apple's published breakdown (watchOS 26): **Duration 50 + Bedtime consistency 30
/// + Interruptions 20**. Duration is the dominant factor and its deductions
/// *accelerate* below a fixed 7 h 50 m full-credit mark (≈13 pts gone at 2 h short),
/// so a short night always costs you — it is NOT graded against your own short
/// average. We replicate **Duration + Interruptions** (the 70 points we can measure
/// from HealthKit samples) and rescale to 100; **consistency** needs ~13 nights of
/// bedtime history we don't track yet, so it's assumed neutral for now (documented,
/// not faked). That makes us run a touch higher than Apple — the gap is the
/// consistency factor — but the duration grading now matches.
///
/// Two ways to turn last night into the curve's start-of-day sleep pressure ("debt"):
///   • Sleep Score — Apple-style duration + interruptions (needs Apple-Watch-grade data).
///   • Hours — duration only (works with any tracker, Oura, or a manual log).
public enum SleepScore {

    /// Hours of sleep that earn full duration credit — Apple's fixed 7 h 50 m mark.
    /// A genuinely higher personal need (`needHours`) raises the bar; a *lower*
    /// average never lowers it (so chronic short sleep can't inflate the score).
    static let fullCreditHours = 7.0 + 50.0 / 60.0   // 7h50m ≈ 7.833

    /// Apple's three component caps.
    static let durationCap = 50.0
    static let interruptionCap = 20.0
    static let consistencyCap = 30.0   // not yet measured — see note above

    /// 0–100, Apple-style. `asleepHours` is time actually asleep; `needHours` is the
    /// user's own sleep need (only used to *raise* the full-credit bar); `efficiency`
    /// is asleep ÷ time-in-bed, our proxy for Apple's interruption factor.
    ///
    /// Pass `bedtimeMinutes` (last night's bedtime, minutes from an evening anchor)
    /// and `normalBedtimeMinutes` (the median of recent nights) once enough history
    /// exists to score the consistency factor — then the full 100 points are used.
    /// Without them, consistency is assumed neutral and the measured 70 are rescaled.
    public static func score(asleepHours: Double, needHours: Double, efficiency: Double,
                             bedtimeMinutes: Int? = nil, normalMinutes: Int? = nil) -> Int {
        guard asleepHours > 0 else { return 0 }
        let dur = durationPoints(asleepHours: asleepHours, needHours: needHours)
        let interr = interruptionPoints(efficiency: efficiency)
        if let bt = bedtimeMinutes, let normal = normalMinutes {
            let cons = consistencyPoints(bedtimeMinutes: bt, normalMinutes: normal)
            return Int((dur + interr + cons).rounded())   // full Duration + Interruptions + Consistency
        }
        // Rescale the 70 points we measure to a 0–100 score (consistency assumed neutral).
        return Int(((dur + interr) / (durationCap + interruptionCap) * 100).rounded())
    }

    /// Consistency points (0…30) from how far last night's bedtime drifted from your
    /// recent normal — Apple's rule: going to bed *later* costs ~1 pt per 5 min beyond
    /// a 15-min grace (−10 at +1 h, 0 at +2.5 h); going to bed *earlier* is free up to
    /// an hour, then a gentle −1 per 30 min (max −6). Bedtimes wrap around midnight.
    public static func consistencyPoints(bedtimeMinutes: Int, normalMinutes: Int) -> Double {
        var delta = Double((bedtimeMinutes - normalMinutes) % 1440)   // + later, − earlier
        if delta > 720 { delta -= 1440 }
        if delta < -720 { delta += 1440 }
        let penalty: Double
        if delta >= 0 {
            penalty = min(max(delta - 15, 0) * (10.0 / 45.0), consistencyCap)
        } else {
            penalty = min(max(-delta - 60, 0) / 30.0, 6)
        }
        return min(max(consistencyCap - penalty, 0), consistencyCap)
    }

    /// Duration points (0…50). Deductions accelerate the further you fall below the
    /// full-credit mark — fit to Apple's anchors (≈5 pts at 1 h short, 13 at 2 h,
    /// >20 at 3 h): `deduction ≈ 3.5·h + 1.5·h²` for `h` hours short.
    static func durationPoints(asleepHours: Double, needHours: Double) -> Double {
        let ref = max(needHours, fullCreditHours)
        let short = max(0, ref - asleepHours)
        let deduction = 3.5 * short + 1.5 * short * short
        return min(max(durationCap - deduction, 0), durationCap)
    }

    /// Interruption points (0…20) from sleep efficiency (asleep ÷ in-bed). No penalty
    /// up to ~3% awake; ~50 min awake on a full night (~12% of in-bed) ≈ −10, matching
    /// Apple's "50 min awake → −10."
    static func interruptionPoints(efficiency: Double) -> Double {
        let eff = min(max(efficiency, 0), 1)
        let awake = max(0, (1 - eff) - 0.03)
        let deduction = awake * 105
        return min(max(interruptionCap - deduction, 0), interruptionCap)
    }

    /// Plain-words band — Apple's watchOS 26.2 tiers.
    public static func label(_ score: Int) -> String {
        switch score {
        case 90...:    return "Very High"
        case 75..<90:  return "High"
        case 60..<75:  return "OK"
        case 41..<60:  return "Low"
        default:       return "Very Low"
        }
    }

    /// Map a 0–100 score to the curve's start-of-day sleep pressure (0.05 rested …
    /// 0.9 depleted) — the Sleep-Score basis.
    public static func debt(fromScore score: Int) -> Double {
        let s = Double(min(max(score, 0), 100)) / 100
        return min(max(0.05 + (1 - s) * 0.85, 0.05), 0.9)
    }

    /// Hours-only debt — the simple "sleep debt" basis, for any tracker that just
    /// logs duration.
    public static func debt(asleepHours: Double, needHours: Double) -> Double {
        guard needHours > 0 else { return 0.9 }
        return min(max(1 - asleepHours / needHours, 0.05), 0.9)
    }
}
