//
//  AlertnessProvider.swift
//  SleepBank
//
//  One place that assembles the day's AlertnessRhythm from HealthKit + nap history,
//  so the curve card, the home ring readout, and (via a stored snapshot) the widget
//  all show the *same* "you are here" number and phase label.
//

import Foundation
import SleepBankCore

enum AlertnessProvider {

    /// Today's completed naps that reached sleep, as rhythm discharges.
    static func napsToday(store: NapDecisionStore = .shared, now: Date) -> [AlertnessRhythm.Nap] {
        let cal = Calendar.current
        return store.records.compactMap { r -> AlertnessRhythm.Nap? in
            guard let onset = r.onset, cal.isDate(r.start, inSameDayAs: now) else { return nil }
            let asleep = r.end.timeIntervalSince(onset)
            let fullness = min(asleep / r.type.targetWakeAfterOnset, 1)
            return AlertnessRhythm.Nap(end: r.end, type: r.type, fullness: fullness)
        }
    }

    /// The day's alertness rhythm from last night's sleep + today's naps, morning
    /// light, and morning movement.
    static func rhythm(health: HealthKitService = .shared,
                       store: NapDecisionStore = .shared, now: Date) -> AlertnessRhythm {
        let summary = health.lastNightSleep
        let typical = summary?.averageLast7Days ?? health.sleepAverage7Day
        let need = max(typical > 0 ? typical : 7.5, 6)
        let healthAsleep = summary?.totalHours ?? 0
        let efficiency = summary?.efficiency ?? 0
        let wake = summary?.wakeTime ?? Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: now) ?? now

        // Fall back to a manual "how long did you sleep" entry when HealthKit has none.
        let manual = ManualSleepStore.shared.today
        let asleep = healthAsleep > 0 ? healthAsleep : (manual ?? 0)
        // Manual entries have no efficiency, so force the hours basis for them.
        let basis: SleepBasis = healthAsleep > 0 ? SleepBasis.current : .hours

        // Bedtime consistency (Apple's 3rd factor) — last night's bedtime vs the
        // rolling normal. Only available with HealthKit sleep + enough history.
        let bedtimeMinutes = healthAsleep > 0 ? summary?.bedtime.map(BedtimeHistoryStore.minutesFrom6pm) ?? nil : nil
        let normalMinutes = BedtimeHistoryStore.shared.normalMinutes
        let spreadMinutes = BedtimeHistoryStore.shared.spreadMinutes

        return AlertnessRhythm(
            wakeTime: wake,
            sleepDebt: sleepDebt(asleep: asleep, need: need, efficiency: efficiency, basis: basis,
                                 deepHours: summary?.deepHours ?? 0, remHours: summary?.remHours ?? 0,
                                 bedtimeMinutes: bedtimeMinutes, normalMinutes: normalMinutes,
                                 spreadMinutes: spreadMinutes),
            naps: napsToday(store: store, now: now),
            isShortNight: asleep > 0 && asleep < need - 0.75,
            morningLightDose: AlertnessRhythm.morningLightDose(minutes: health.daylightToday.morning),
            morningActivityDose: AlertnessRhythm.morningActivityDose(minutes: health.morningActivityMinutes)
        )
    }

    /// The curve's start-of-day sleep pressure, per the chosen basis. No data → assume
    /// rested (don't penalize someone without a tracker).
    static func sleepDebt(asleep: Double, need: Double, efficiency: Double, basis: SleepBasis,
                          deepHours: Double = 0, remHours: Double = 0,
                          bedtimeMinutes: Int? = nil, normalMinutes: Int? = nil,
                          spreadMinutes: Int? = nil) -> Double {
        guard asleep > 0 else { return 0.05 }
        let useScore: Bool
        switch basis {
        case .hours:       useScore = false
        case .sleepScore:  useScore = true
        case .auto:        useScore = efficiency > 0 && efficiency < 0.999   // has awake data → quality tracking
        }
        if useScore {
            return SleepScore.debt(fromScore: SleepScore.score(
                asleepHours: asleep, needHours: need, efficiency: efficiency,
                deepHours: deepHours, remHours: remHours,
                bedtimeMinutes: bedtimeMinutes, normalMinutes: normalMinutes,
                spreadMinutes: spreadMinutes))
        }
        return SleepScore.debt(asleepHours: asleep, needHours: need)
    }

    static func pct(_ level: Double) -> Int { Int((level * 100).rounded()) }
    static func phaseLabel(_ now: Date) -> String { AlertnessRhythm.phaseLabel(at: now) }
}
