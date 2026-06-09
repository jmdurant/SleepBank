import Foundation

/// A *predicted* daily alertness curve — the two-process model (Borbély), rendered
/// honestly from data we actually have. It is illustrative, not a measurement of
/// your real alertness: it shows the *shape* of a typical day and how last night's
/// sleep and today's naps move it.
///
/// Alertness ≈ **C − S**:
/// - **Process C** (circadian) — a non-linear rhythm independent of time awake:
///   a late-morning rise, a **post-lunch dip** (~15:30), an early-evening
///   **wake-maintenance zone** (~19:00, the "second wind"), then a night plunge.
/// - **Process S** (homeostatic sleep pressure) — builds the longer you're awake
///   and *discharges* when you sleep. Its **start-of-day value is set by last
///   night's sleep**: a short night leaves S only partly discharged, so the whole
///   curve sits lower all day and the gap widens into the afternoon — exactly the
///   effect you feel after sleeping badly. Each nap today discharges some S, lifting
///   the rest-of-day curve (the lift fades over the subjective-benefit window,
///   `docs/NAP_BENEFIT_EVIDENCE.md` §2).
public struct AlertnessRhythm: Sendable {

    /// One sampled point on the curve.
    public struct Reading: Equatable, Sendable {
        public let date: Date
        public let level: Double   // 0…1, normalized for display
        public init(date: Date, level: Double) {
            self.date = date
            self.level = level
        }
    }

    /// A nap's contribution: when it ended, its type, and how full it was (asleep
    /// time vs the type's target, 0…1).
    public struct Nap: Sendable {
        public let end: Date
        public let type: NapType
        public let fullness: Double
        public init(end: Date, type: NapType, fullness: Double) {
            self.end = end
            self.type = type
            self.fullness = max(0, min(fullness, 1))
        }
    }

    public let wakeTime: Date
    /// 0…1 residual sleep pressure at wake — higher means a shorter night.
    public let sleepDebt: Double
    public let naps: [Nap]
    /// True when last night was short relative to the user's own normal — drives
    /// the "your curve sits lower today" annotation.
    public let isShortNight: Bool
    /// 0…1 dose of morning daylight (e.g. an early walk). Drives a small, morning-
    /// concentrated lift on Process C — justified by the cortisol awakening response
    /// (`docs/DAYLIGHT_EVIDENCE.md` §3a), NOT the weak acute photic-alerting effect.
    /// Deliberately small: the larger payoff (anchoring + better sleep tonight) is
    /// downstream and is carried by messaging, not the curve.
    public let morningLightDose: Double
    /// 0…1 dose of morning physical activity (e.g. a morning walk). A second,
    /// independent morning lift — exercise is a non-photic zeitgeber that advances
    /// the clock (Youngstedt 2019 exercise PRC) plus an acute arousal effect, so it
    /// stacks with light. Combined morning lift is capped so it stays modest.
    public let morningActivityDose: Double
    private let calendar: Calendar

    public init(wakeTime: Date, sleepDebt: Double, naps: [Nap] = [],
                isShortNight: Bool = false, morningLightDose: Double = 0,
                morningActivityDose: Double = 0, calendar: Calendar = .current) {
        self.wakeTime = wakeTime
        self.sleepDebt = max(0.05, min(sleepDebt, 0.9))
        self.naps = naps
        self.isShortNight = isShortNight
        self.morningLightDose = max(0, min(morningLightDose, 1))
        self.morningActivityDose = max(0, min(morningActivityDose, 1))
        self.calendar = calendar
    }

    /// Build from last night's sleep. `sleptHours` is asleep time; `typicalHours`
    /// is the user's own recent average (the reference for "short"). Falls back to
    /// sensible defaults when Health data is missing.
    public static func fromSleep(wakeTime: Date?, sleptHours: Double, typicalHours: Double,
                                 naps: [Nap] = [], morningLightDose: Double = 0,
                                 morningActivityDose: Double = 0, now: Date,
                                 calendar: Calendar = .current) -> AlertnessRhythm {
        let need = max(typicalHours > 0 ? typicalHours : 7.5, 6)
        let wake = wakeTime ?? calendar.date(bySettingHour: 7, minute: 0, second: 0, of: now) ?? now
        // No data → assume an average night rather than a catastrophic one.
        let effectiveHours = sleptHours > 0 ? sleptHours : need
        let debt = 1 - (effectiveHours / need)
        let short = sleptHours > 0 && sleptHours < need - 0.75
        return AlertnessRhythm(wakeTime: wake, sleepDebt: debt, naps: naps,
                               isShortNight: short, morningLightDose: morningLightDose,
                               morningActivityDose: morningActivityDose, calendar: calendar)
    }

    /// Convert morning daylight minutes into a 0…1 dose with diminishing returns.
    /// `target` is a *heuristic* "got meaningful morning light" amount — the
    /// evidence supports an illuminance threshold, not a validated minutes dose, so
    /// this is intentionally soft (see `docs/DAYLIGHT_EVIDENCE.md` §4).
    public static func morningLightDose(minutes: Double, target: Double = 20) -> Double {
        guard target > 0 else { return 0 }
        return max(0, min(minutes / target, 1))
    }

    /// Convert morning exercise minutes into a 0…1 dose (diminishing returns). Same
    /// soft, heuristic shape as the light dose.
    public static func morningActivityDose(minutes: Double, target: Double = 15) -> Double {
        guard target > 0 else { return 0 }
        return max(0, min(minutes / target, 1))
    }

    // MARK: - Model constants

    private static let omega = 2 * Double.pi / 24
    private static let tauRise: Double = 18.2     // h — Process S build constant (Daan)
    private static let tauRelief: Double = 2.5    // h — nap relief fade (subjective-benefit window)
    private static let morningLightPeak: Double = 0.12     // raw units (~+0.07 on the 0…1 display)
    private static let morningActivityPeak: Double = 0.10  // a second, independent morning lift
    private static let morningLiftCap: Double = 0.18        // combined morning lift stays modest

    // MARK: - The two processes

    /// Circadian alertness (Process C) at a clock hour — bimodal, with the
    /// post-lunch dip and the evening wake-maintenance zone.
    private func circadian(hour t: Double) -> Double {
        let w = Self.omega
        let main = 0.55 * sin(w * (t - 11))                 // day-up / night-down, peak ~17, trough ~5
        let dip  = 0.42 * exp(-pow((t - 15.5) / 2.0, 2))    // post-lunch dip
        let wmz  = 0.18 * exp(-pow((t - 19.0) / 2.2, 2))    // evening "second wind"
        return main - dip + wmz
    }

    /// Sleep pressure (Process S) at a moment: rises from the start-of-day deficit
    /// toward saturation, minus the relief from naps taken so far.
    private func pressure(at date: Date, extraNap: Nap? = nil) -> Double {
        let awake = max(0, date.timeIntervalSince(wakeTime) / 3600)
        var s = 1 - (1 - sleepDebt) * exp(-awake / Self.tauRise)
        for nap in naps { s -= relief(of: nap, at: date) }
        if let extraNap { s -= relief(of: extraNap, at: date) }
        return max(0, s)
    }

    private func relief(of nap: Nap, at date: Date) -> Double {
        guard date >= nap.end else { return 0 }
        let dt = date.timeIntervalSince(nap.end) / 3600
        let depth = (nap.type == .cycle ? 0.42 : 0.16) * nap.fullness
        return depth * exp(-dt / Self.tauRelief)
    }

    /// Morning lift — two stacked, independently-evidenced morning behaviours:
    /// light (cortisol awakening response) and physical activity (exercise zeitgeber
    /// + acute arousal). A bump concentrated in the morning, peaking ~1.5 h after
    /// waking and effectively gone by midday; combined magnitude capped so it stays
    /// modest. Zero before wake.
    private func morningLift(at date: Date) -> Double {
        let combined = min(Self.morningLightPeak * morningLightDose
                           + Self.morningActivityPeak * morningActivityDose,
                           Self.morningLiftCap)
        guard combined > 0 else { return 0 }
        let awake = date.timeIntervalSince(wakeTime) / 3600
        guard awake >= 0 else { return 0 }
        let shape = exp(-pow((awake - 1.5) / 2.5, 2))   // peak ~1.5 h post-wake, fades by ~midday
        return combined * shape
    }

    /// Raw (C − S + morning light) before display normalization — the single source
    /// of truth for every sampling method.
    private func rawLevel(at date: Date, extraNap: Nap? = nil) -> Double {
        circadian(hour: hour(of: date)) - pressure(at: date, extraNap: extraNap) + morningLift(at: date)
    }

    private func hour(of date: Date) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
    }

    /// Map raw (C − S) onto a fixed 0…1 display range. Fixed (not per-day) so a bad
    /// night genuinely reads lower than a good one.
    private func normalize(_ raw: Double) -> Double {
        let lo = -1.3, hi = 0.5
        return max(0, min((raw - lo) / (hi - lo), 1))
    }

    // MARK: - Public sampling

    /// Predicted alertness (0…1) at a moment, including naps taken so far.
    public func level(at date: Date) -> Double {
        normalize(rawLevel(at: date))
    }

    /// Predicted alertness if a hypothetical nap were taken `napAt`.
    public func level(at date: Date, withNapAt napAt: Date, type: NapType) -> Double {
        let nap = Nap(end: napAt.addingTimeInterval(type.targetWakeAfterOnset), type: type, fullness: 1)
        return normalize(rawLevel(at: date, extraNap: nap))
    }

    /// The baseline curve sampled across a window.
    public func readings(from start: Date, to end: Date, step: TimeInterval = 900) -> [Reading] {
        stride(from: start, through: end, step: step).map { Reading(date: $0, level: level(at: $0)) }
    }

    /// The "where you could be" curve: a hypothetical nap starting `napAt`.
    public func projectedReadings(napType: NapType, napAt: Date,
                                  from start: Date, to end: Date, step: TimeInterval = 900) -> [Reading] {
        let nap = Nap(end: napAt.addingTimeInterval(napType.targetWakeAfterOnset),
                      type: napType, fullness: 1)
        return stride(from: start, through: end, step: step).map {
            Reading(date: $0, level: normalize(rawLevel(at: $0, extraNap: nap)))
        }
    }
}

/// `stride` over Dates by a time interval.
private func stride(from start: Date, through end: Date, step: TimeInterval) -> [Date] {
    guard step > 0, end >= start else { return [start] }
    var result: [Date] = []
    var t = start
    while t <= end.addingTimeInterval(0.5) {
        result.append(t)
        t = t.addingTimeInterval(step)
    }
    return result
}
