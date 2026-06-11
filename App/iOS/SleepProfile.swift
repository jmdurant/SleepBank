//
//  SleepProfile.swift
//  SleepBank
//
//  The user's *typical* schedule — bedtime, wake time, and sleep need — collected at
//  the guided start and editable in Settings. This is the stable, habitual profile
//  (their chronotype), distinct from last night's actual sleep:
//   • Phase — *when* the curve's peaks and dip land — comes from this profile (the
//     sleep midpoint phase-shifts the whole curve, owl later / lark earlier).
//   • Height — *how high* the curve sits today — still comes from last night's sleep.
//  So a single late night never lurches your chronotype.
//

import Foundation
import SleepBankCore

@Observable
final class SleepProfile {
    static let shared = SleepProfile()

    /// Typical bedtime, minutes from midnight (e.g. 23:00 → 1380).
    var bedtimeMinutes: Int = UserDefaults.standard.object(forKey: K.bedtime) as? Int ?? 23 * 60 {
        didSet { UserDefaults.standard.set(bedtimeMinutes, forKey: K.bedtime) }
    }
    /// Typical wake time, minutes from midnight (e.g. 07:00 → 420).
    var wakeMinutes: Int = UserDefaults.standard.object(forKey: K.wake) as? Int ?? 7 * 60 {
        didSet { UserDefaults.standard.set(wakeMinutes, forKey: K.wake) }
    }
    /// Typical sleep need, hours.
    var needHours: Double = UserDefaults.standard.object(forKey: K.need) as? Double ?? 8.0 {
        didSet { UserDefaults.standard.set(needHours, forKey: K.need) }
    }
    /// Whether the user has actually set/confirmed a profile (vs running on defaults).
    var isSet: Bool = UserDefaults.standard.bool(forKey: K.isSet) {
        didSet { UserDefaults.standard.set(isSet, forKey: K.isSet) }
    }

    private enum K {
        static let bedtime = "profileBedtime"
        static let wake = "profileWake"
        static let need = "profileNeed"
        static let isSet = "profileIsSet"
    }

    /// The chronotype phase shift the curve should use (0 when no profile is set).
    var circadianShiftHours: Double {
        isSet ? AlertnessRhythm.phaseShift(bedtimeMinutes: bedtimeMinutes, wakeMinutes: wakeMinutes) : 0
    }

    /// Typical wake as a Date on `day` — the curve's fallback when HealthKit has no
    /// actual wake time for last night.
    func typicalWake(on day: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard isSet else { return nil }
        return calendar.date(bySettingHour: wakeMinutes / 60, minute: wakeMinutes % 60, second: 0, of: day)
    }

    func update(bedtime: Int, wake: Int, need: Double) {
        bedtimeMinutes = bedtime
        wakeMinutes = wake
        needHours = need
        isSet = true
    }
}
