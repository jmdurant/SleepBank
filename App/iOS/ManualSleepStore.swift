//
//  ManualSleepStore.swift
//  SleepBank
//
//  A manual "how long did you sleep last night?" entry, for when there's no
//  HealthKit sleep data (no Apple Watch, Oura not syncing, etc.). Seeds the Sleep
//  Score / curve offset so everyone gets a grounded Alert Score. Per-day; clears on
//  a new day.
//

import Foundation

@Observable
final class ManualSleepStore {
    static let shared = ManualSleepStore()

    private var hours: Double = UserDefaults.standard.double(forKey: "manualSleepHours")
    private var dayStamp: Double = UserDefaults.standard.double(forKey: "manualSleepDay")

    private static func todayStamp() -> Double {
        Calendar.current.startOfDay(for: Date()).timeIntervalSinceReferenceDate
    }

    /// Manually-logged hours for last night, if entered today.
    var today: Double? {
        (dayStamp == Self.todayStamp() && hours > 0) ? hours : nil
    }

    func log(hours: Double) {
        self.hours = hours
        self.dayStamp = Self.todayStamp()
        UserDefaults.standard.set(hours, forKey: "manualSleepHours")
        UserDefaults.standard.set(dayStamp, forKey: "manualSleepDay")
    }
}
