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
        return AlertnessRhythm.fromSleep(
            wakeTime: summary?.wakeTime,
            sleptHours: summary?.totalHours ?? 0,
            typicalHours: typical,
            naps: napsToday(store: store, now: now),
            morningLightDose: AlertnessRhythm.morningLightDose(minutes: health.daylightToday.morning),
            morningActivityDose: AlertnessRhythm.morningActivityDose(minutes: health.morningActivityMinutes),
            now: now
        )
    }

    static func pct(_ level: Double) -> Int { Int((level * 100).rounded()) }
    static func phaseLabel(_ now: Date) -> String { AlertnessRhythm.phaseLabel(at: now) }
}
