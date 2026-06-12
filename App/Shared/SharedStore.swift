//
//  SharedStore.swift
//  SleepBank (shared — app + widget extension)
//
//  Tiny App Group-backed store so the home-screen / Smart-Stack widget can read
//  the latest nap + health summary the app writes. The watch is the source of
//  truth for nap totals (it forwards them on nap end); the phone writes
//  last-night sleep and resting HR from HealthKit.
//

import Foundation

enum SharedStore {
    static let appGroup = "group.com.doctordurant.sleepbank"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static var napsToday: Int {
        get { defaults?.integer(forKey: "napsToday") ?? 0 }
        set { defaults?.set(newValue, forKey: "napsToday") }
    }
    static var minutesToday: Int {
        get { defaults?.integer(forKey: "minutesToday") ?? 0 }
        set { defaults?.set(newValue, forKey: "minutesToday") }
    }
    static var napActive: Bool {
        get { defaults?.bool(forKey: "napActive") ?? false }
        set { defaults?.set(newValue, forKey: "napActive") }
    }
    static var lastNightHours: Double {
        get { defaults?.double(forKey: "lastNightHours") ?? 0 }
        set { defaults?.set(newValue, forKey: "lastNightHours") }
    }
    static var restingHR: Int {
        get { defaults?.integer(forKey: "restingHR") ?? 0 }
        set { defaults?.set(newValue, forKey: "restingHR") }
    }
    /// Consecutive days with morning daylight — for the widget.
    static var morningLightStreak: Int {
        get { defaults?.integer(forKey: "morningLightStreak") ?? 0 }
        set { defaults?.set(newValue, forKey: "morningLightStreak") }
    }
    /// Today's daylight + morning movement (minutes) for the Daylight widget.
    static var daylightTotalMin: Int {
        get { defaults?.integer(forKey: "daylightTotalMin") ?? 0 }
        set { defaults?.set(newValue, forKey: "daylightTotalMin") }
    }
    static var daylightMorningMin: Int {
        get { defaults?.integer(forKey: "daylightMorningMin") ?? 0 }
        set { defaults?.set(newValue, forKey: "daylightMorningMin") }
    }
    static var morningActivityMin: Int {
        get { defaults?.integer(forKey: "morningActivityMin") ?? 0 }
        set { defaults?.set(newValue, forKey: "morningActivityMin") }
    }
    /// JSON snapshot of the day's alertness-rhythm inputs, so the widget can compute
    /// the live "you are here" % itself at each timeline entry. Decoded by
    /// `RhythmSnapshot` (kept out of this pure-Foundation file so the watch widget,
    /// which shares it but not SleepBankCore, still builds).
    static var rhythmSnapshot: Data? {
        get { defaults?.data(forKey: "rhythmSnapshot") }
        set { defaults?.set(newValue, forKey: "rhythmSnapshot") }
    }
    /// Pre-computed `PlanSummary` digest (JSON) for the watch complication.
    static var planSummary: Data? {
        get { defaults?.data(forKey: "planSummary") }
        set { defaults?.set(newValue, forKey: "planSummary") }
    }
}
