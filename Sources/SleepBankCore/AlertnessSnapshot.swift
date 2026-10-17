import Foundation

public struct AlertnessSnapshot: Codable {
    public struct NapInput: Codable {
        public var end: Date
        public var typeRaw: String
        public var fullness: Double
    }

    public var wakeTime: Date
    public var sleepDebt: Double
    public var isShortNight: Bool
    public var morningLightDose: Double
    public var morningActivityDose: Double
    public var circadianShiftHours: Double = 0
    public var naps: [NapInput]
    public var morningLightStreak: Int
    public var sleepDay: Date?
    public var updated: Date

    public init(rhythm: AlertnessRhythm, morningLightStreak: Int, updated: Date, sleepDay: Date?) {
        self.wakeTime = rhythm.wakeTime
        self.sleepDebt = rhythm.sleepDebt
        self.isShortNight = rhythm.isShortNight
        self.morningLightDose = rhythm.morningLightDose
        self.morningActivityDose = rhythm.morningActivityDose
        self.circadianShiftHours = rhythm.circadianShiftHours
        self.naps = rhythm.naps.map { NapInput(end: $0.end, typeRaw: $0.type.rawValue, fullness: $0.fullness) }
        self.morningLightStreak = morningLightStreak
        self.sleepDay = sleepDay
        self.updated = updated
    }

    /// A prediction is usable only for the day with an actual sleep basis.
    /// Older snapshots without sleepDay decode safely but cannot produce a score.
    public func rebuild(asOf date: Date = Date(), calendar: Calendar = .current) -> AlertnessRhythm? {
        guard let sleepDay,
              calendar.isDate(sleepDay, inSameDayAs: date),
              calendar.isDate(updated, inSameDayAs: date) else { return nil }
        let napInputs = naps
        let naps = napInputs.map {
            AlertnessRhythm.Nap(end: $0.end, type: NapType(rawValue: $0.typeRaw) ?? .power, fullness: $0.fullness)
        }
        return AlertnessRhythm(wakeTime: wakeTime, sleepDebt: sleepDebt, naps: naps,
                               isShortNight: isShortNight, morningLightDose: morningLightDose,
                               morningActivityDose: morningActivityDose,
                               circadianShiftHours: circadianShiftHours, calendar: calendar)
    }

}
