//
//  AlertnessProvider.swift
//  SleepBank
//
//  One place that assembles the day's AlertnessRhythm from HealthKit + nap history,
//  so the curve card, the home ring readout, and (via a stored snapshot) the widget
//  all show the *same* "you are here" number and phase label.
//

import Foundation
import WidgetKit
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
        let profile = SleepProfile.shared
        let summary = health.lastNightSleep
        // Need: the user's stated typical need (profile) wins, else the rolling average.
        let typical = summary?.averageLast7Days ?? health.sleepAverage7Day
        let need = profile.isSet ? max(profile.needHours, 6) : max(typical > 0 ? typical : 7.5, 6)
        let healthAsleep = summary?.totalHours ?? 0
        // Wake for Process S / morning lift: last night's actual wake, else the
        // profile's typical wake, else 7am.
        let wake = summary?.wakeTime ?? profile.typicalWake(on: now)
            ?? Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: now) ?? now

        // Fall back to a manual "how long did you sleep" entry when HealthKit has none.
        let manual = ManualSleepStore.shared.today
        let usingManual = healthAsleep == 0 && manual != nil
        let asleep = healthAsleep > 0 ? healthAsleep : (manual ?? 0)

        // A manual estimate now carries an interruptions estimate too (the reported
        // awakenings, ~7 min each → an efficiency proxy), so it can drive a real
        // *estimated Sleep Score* rather than duration-only debt. Honor the user's
        // basis setting: explicit Hours stays duration-only; Auto/Sleep Score use the
        // estimated score. Consistency is left neutral (we can't know last night's
        // bedtime without a tracker).
        let manualEfficiency: Double = {
            let awakenings = ManualSleepStore.shared.todayAwakenings ?? 0
            let inBed = asleep + Double(awakenings) * 7.0 / 60.0   // ~7 min awake per awakening
            return inBed > 0 ? asleep / inBed : 1.0
        }()
        let efficiency = usingManual ? manualEfficiency : (summary?.efficiency ?? 0)
        let basis: SleepBasis = usingManual
            ? (SleepBasis.current == .hours ? .hours : .sleepScore)
            : SleepBasis.current

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
            morningActivityDose: AlertnessRhythm.morningActivityDose(minutes: health.morningActivityMinutes),
            circadianShiftHours: profile.circadianShiftHours
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
    static func phaseLabel(_ now: Date) -> String {
        AlertnessRhythm.phaseLabel(at: now, shiftHours: SleepProfile.shared.circadianShiftHours)
    }

    /// Rebuild the rhythm snapshot and push it everywhere downstream (widget + watch)
    /// — call after anything that changes the curve's inputs (manual sleep, profile).
    static func publishSnapshot(health: HealthKitService = .shared) {
        let snapshot = RhythmSnapshot(rhythm: rhythm(now: Date()),
                                      morningLightStreak: health.morningLightStreak, updated: Date())
        snapshot.save()
        PhoneConnectivity.shared.sendDailySummary(
            samples: health.lastNightSamples,
            morningLightStreak: health.morningLightStreak,
            rhythmSnapshot: try? JSONEncoder().encode(snapshot))
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Whether we have a real sleep basis for today — HealthKit sleep *or* a manual
    /// estimate. Without one we shouldn't show a confident Alertness Score (the curve
    /// would default to "rested" and read near the ceiling, which is misleading); the
    /// UI prompts for an estimate instead.
    static func hasSleepData(health: HealthKitService = .shared) -> Bool {
        (health.lastNightSleep?.totalHours ?? 0) > 0 || ManualSleepStore.shared.today != nil
    }

    /// True once HealthKit has finished its first load, so a "no sleep data" state is
    /// real (not just "still loading").
    static func sleepDataLoaded(health: HealthKitService = .shared) -> Bool {
        health.lastRefresh != nil
    }
}
