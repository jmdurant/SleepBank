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

    /// A hypothetical bout of physical activity placed on the curve. `intensity` sets
    /// the size of the *acute* arousal bump (a walk lifts less than a workout, and both
    /// less than a nap); `outdoors` adds the light/circadian-anchoring layer — its
    /// payoff is downstream (better sleep tonight), carried by messaging, not a big
    /// acute curve lift, per `docs/DAYLIGHT_EVIDENCE.md`.
    public struct Activity: Sendable, Identifiable {
        public enum Intensity: String, Sendable, CaseIterable { case walk, workout }
        public let id: String
        public let intensity: Intensity
        public let outdoors: Bool
        public let start: Date
        public let duration: TimeInterval
        public init(id: String = "activity", intensity: Intensity, outdoors: Bool,
                    start: Date, duration: TimeInterval) {
            self.id = id
            self.intensity = intensity
            self.outdoors = outdoors
            self.start = start
            self.duration = duration
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

    /// Where you sit in the circadian day, in plain words. Shared by the curve card,
    /// the home ring readout, and the widget so they all label the moment the same.
    public static func phaseLabel(at date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case ..<10:    return "Morning rise"
        case 10..<13:  return "Late-morning peak"
        case 13..<16:  return "Post-lunch dip"
        case 16..<18:  return "Afternoon"
        case 18..<21:  return "Evening — second wind"
        default:       return "Wind-down"
        }
    }

    // MARK: - Model constants

    private static let omega = 2 * Double.pi / 24
    private static let tauRise: Double = 18.2     // h — Process S build constant (Daan)
    private static let tauRelief: Double = 2.6    // h — subjective-benefit fade
    private static let tauHomeoPower: Double = 4.0   // h — a light nap's homeostatic discharge fades by evening
    private static let tauHomeoCycle: Double = 9.0   // h — a deep nap's discharge lingers to bedtime (why a late one ruins sleep)
    private static let tauNapOnset: Double = 0.7  // h — how fast the benefit comes on (saturating, so the peak is rounded)
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
    private func pressure(at date: Date, extraNaps: [Nap] = []) -> Double {
        let awake = max(0, date.timeIntervalSince(wakeTime) / 3600)
        var s = 1 - (1 - sleepDebt) * exp(-awake / Self.tauRise)
        for nap in naps { s -= relief(of: nap, at: date) }
        for nap in extraNaps { s -= relief(of: nap, at: date) }
        return max(0, s)
    }

    private func relief(of nap: Nap, at date: Date) -> Double {
        let onset = nap.end.addingTimeInterval(-nap.type.targetWakeAfterOnset)
        let v = date.timeIntervalSince(onset) / 3600   // hours since sleep onset
        guard v > 0 else { return 0 }
        // A smooth impulse response: a saturating onset (the benefit builds over the
        // nap and the first hour after, clearing inertia) times a bi-exponential decay
        // — a fast subjective component plus a slow homeostatic one. A power nap is
        // mostly the quick bump and fades by evening; a cycle nap carries more in the
        // durable slow tail, so it lifts a little higher, lasts far longer, and — taken
        // late — keeps the evening elevated, stealing tonight's sleepiness. The product
        // of two smooth curves is itself smooth everywhere: no corner at the peak or
        // where it rejoins the baseline. Depths stay modest so relief never drives
        // pressure to zero (which would pin the curve at the circadian max).
        let subjective = (nap.type == .cycle ? 0.18 : 0.23) * nap.fullness
        let homeostatic = (nap.type == .cycle ? 0.22 : 0.05) * nap.fullness
        let tauHomeo = nap.type == .cycle ? Self.tauHomeoCycle : Self.tauHomeoPower
        let onsetRamp = 1 - exp(-v / Self.tauNapOnset)
        let decay = subjective * exp(-v / Self.tauRelief) + homeostatic * exp(-v / tauHomeo)
        return decay * onsetRamp
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

    /// Acute arousal from a bout of physical activity — a modest, short-lived lift
    /// (raised catecholamines + core temp), NOT a sleep-pressure discharge like a nap.
    /// Smooth: builds from onset, peaks ~35 min in, fades over ~1.5 h. A workout lifts
    /// about twice a walk, and both stay well under a nap. Placed late, the lingering
    /// tail keeps the evening elevated — the honest "exercise too close to bed" cost.
    private func arousal(of a: Activity, at date: Date) -> Double {
        let u = date.timeIntervalSince(a.start) / 3600
        guard u > 0 else { return 0 }
        let coef = a.intensity == .workout ? 0.21 : 0.10
        return coef * (1 - exp(-u / 0.5)) * exp(-u / 1.6)
    }

    /// Raw (C − S + morning light + activity arousal) before display normalization —
    /// the single source of truth for every sampling method.
    private func rawLevel(at date: Date, extraNaps: [Nap] = [], activities: [Activity] = []) -> Double {
        circadian(hour: hour(of: date)) - pressure(at: date, extraNaps: extraNaps) + morningLift(at: date)
            + activities.reduce(0) { $0 + arousal(of: $1, at: date) }
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
        return normalize(rawLevel(at: date, extraNaps: [nap]))
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
            Reading(date: $0, level: normalize(rawLevel(at: $0, extraNaps: [nap])))
        }
    }

    /// Alertness at a moment under a whole plan — any number of naps plus activities.
    public func level(at date: Date, naps: [Nap], activities: [Activity]) -> Double {
        normalize(rawLevel(at: date, extraNaps: naps, activities: activities))
    }

    /// The combined "with your plan" curve: naps stacked with activities.
    public func planReadings(naps: [Nap], activities: [Activity],
                             from start: Date, to end: Date, step: TimeInterval = 900) -> [Reading] {
        stride(from: start, through: end, step: step).map {
            Reading(date: $0, level: normalize(rawLevel(at: $0, extraNaps: naps, activities: activities)))
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
