//
//  RhythmSnapshot.swift
//  SleepBank (shared — app + phone widget)
//
//  A Codable snapshot of the day's AlertnessRhythm *inputs*. The app writes it to
//  the App Group after each refresh; the widget reads it and rebuilds the rhythm so
//  it can compute the live "you are here" % at every timeline entry (rather than
//  showing a single stale number). Kept separate from SharedStore.swift because it
//  imports SleepBankCore, which the watch-complication target doesn't link.
//

import Foundation
import SleepBankCore

struct RhythmSnapshot: Codable {
    struct NapInput: Codable {
        var end: Date
        var typeRaw: String
        var fullness: Double
    }

    var wakeTime: Date
    var sleepDebt: Double
    var isShortNight: Bool
    var morningLightDose: Double
    var morningActivityDose: Double
    var circadianShiftHours: Double = 0
    var naps: [NapInput]
    var morningLightStreak: Int
    var updated: Date

    init(rhythm: AlertnessRhythm, morningLightStreak: Int, updated: Date) {
        self.wakeTime = rhythm.wakeTime
        self.sleepDebt = rhythm.sleepDebt
        self.isShortNight = rhythm.isShortNight
        self.morningLightDose = rhythm.morningLightDose
        self.morningActivityDose = rhythm.morningActivityDose
        self.circadianShiftHours = rhythm.circadianShiftHours
        self.naps = rhythm.naps.map { NapInput(end: $0.end, typeRaw: $0.type.rawValue, fullness: $0.fullness) }
        self.morningLightStreak = morningLightStreak
        self.updated = updated
    }

    /// Rebuild the rhythm so the widget can evaluate `level(at:)` for any entry date.
    func rebuild() -> AlertnessRhythm {
        let naps = naps.map {
            AlertnessRhythm.Nap(end: $0.end, type: NapType(rawValue: $0.typeRaw) ?? .power, fullness: $0.fullness)
        }
        return AlertnessRhythm(wakeTime: wakeTime, sleepDebt: sleepDebt, naps: naps,
                               isShortNight: isShortNight, morningLightDose: morningLightDose,
                               morningActivityDose: morningActivityDose,
                               circadianShiftHours: circadianShiftHours)
    }

    // MARK: - App Group persistence

    func save() {
        SharedStore.rhythmSnapshot = try? JSONEncoder().encode(self)
        SharedStore.morningLightStreak = morningLightStreak
    }

    static func load() -> RhythmSnapshot? {
        guard let data = SharedStore.rhythmSnapshot else { return nil }
        return try? JSONDecoder().decode(RhythmSnapshot.self, from: data)
    }
}
