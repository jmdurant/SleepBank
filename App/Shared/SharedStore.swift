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
}
