//
//  ManualSleepStore.swift
//  SleepBank
//
//  A manual "how long did you sleep last night?" entry, for when there's no
//  HealthKit sleep data (no Apple Watch, Oura not syncing, etc.). Seeds the Sleep
//  Score / curve offset so everyone gets a grounded Alertness Score. Per-day; clears on
//  a new day.
//

import Foundation

@Observable
final class ManualSleepStore {
    static let shared = ManualSleepStore()

    private var hours: Double = UserDefaults.standard.double(forKey: "manualSleepHours")
    private var awakenings: Int = UserDefaults.standard.integer(forKey: "manualSleepAwakenings")
    private var dayStamp: Double = UserDefaults.standard.double(forKey: "manualSleepDay")

    private static func todayStamp() -> Double {
        Calendar.current.startOfDay(for: Date()).timeIntervalSinceReferenceDate
    }

    private var isToday: Bool { dayStamp == Self.todayStamp() && hours > 0 }

    /// Manually-logged hours for last night, if entered today.
    var today: Double? { isToday ? hours : nil }

    /// Estimated awakenings for last night, if entered today.
    var todayAwakenings: Int? { isToday ? awakenings : nil }

    func log(hours: Double, awakenings: Int = 0) {
        self.hours = hours
        self.awakenings = awakenings
        self.dayStamp = Self.todayStamp()
        UserDefaults.standard.set(hours, forKey: "manualSleepHours")
        UserDefaults.standard.set(awakenings, forKey: "manualSleepAwakenings")
        UserDefaults.standard.set(dayStamp, forKey: "manualSleepDay")
    }
}
