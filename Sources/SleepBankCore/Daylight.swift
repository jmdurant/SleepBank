import Foundation

/// Time-in-daylight bucketing. Apple's "Time in Daylight" (the Apple Watch
/// ambient-light metric) arrives as intervals of recorded daylight minutes; what
/// matters for the circadian curve isn't just the daily *total* but *when* the
/// light landed — **morning** light anchors and lifts the day's rhythm far more
/// than the same minutes in the afternoon. This splits the day so the booster can
/// weight the morning window separately. Pure and testable; the iOS layer maps
/// HealthKit samples into `Interval`s.
public enum Daylight {

    /// One recorded stretch of daylight: a wall-clock span and the daylight
    /// minutes within it (often ≈ the span, but can be less).
    public struct Interval: Sendable, Equatable {
        public let start: Date
        public let end: Date
        public let minutes: Double
        public init(start: Date, end: Date, minutes: Double) {
            self.start = start
            self.end = end
            self.minutes = minutes
        }
    }

    /// Total recorded daylight minutes.
    public static func total(_ intervals: [Interval]) -> Double {
        intervals.reduce(0) { $0 + $1.minutes }
    }

    /// Daylight minutes overlapping `[from, to)`. Each interval's minutes are
    /// attributed proportionally to how much of its span falls in the range, so an
    /// interval straddling a window boundary contributes its fair share to each.
    public static func minutes(in intervals: [Interval], from: Date, to: Date) -> Double {
        guard to > from else { return 0 }
        var sum = 0.0
        for iv in intervals {
            let span = iv.end.timeIntervalSince(iv.start)
            if span <= 0 {                       // instantaneous sample — count if inside
                if iv.start >= from, iv.start < to { sum += iv.minutes }
                continue
            }
            let overlap = min(iv.end, to).timeIntervalSince(max(iv.start, from))
            if overlap > 0 { sum += iv.minutes * (overlap / span) }
        }
        return sum
    }

    /// Daylight minutes in the clock-morning window `[window.lowerBound,
    /// window.upperBound)` of `day`. Clock-based (not wake-relative) so it works over
    /// historical days where we don't have each day's wake time.
    public static func morningMinutes(in intervals: [Interval], on day: Date,
                                      window: Range<Int> = 5..<11,
                                      calendar: Calendar = .current) -> Double {
        let base = calendar.startOfDay(for: day)
        let from = base.addingTimeInterval(Double(window.lowerBound) * 3600)
        let to = base.addingTimeInterval(Double(window.upperBound) * 3600)
        return minutes(in: intervals, from: from, to: to)
    }

    /// Consecutive days (back from `asOf`) with at least `targetMinutes` of morning
    /// daylight — the "morning light" habit streak, parallel to the nap streak. A
    /// streak that ran through yesterday survives not having logged light *yet*
    /// today (anchored on today or yesterday). Honest: it counts what happened.
    public static func morningStreak(intervals: [Interval], asOf: Date,
                                     targetMinutes: Double = 10, window: Range<Int> = 5..<11,
                                     calendar: Calendar = .current) -> Int {
        func got(_ day: Date) -> Bool {
            morningMinutes(in: intervals, on: day, window: window, calendar: calendar) >= targetMinutes
        }
        let today = calendar.startOfDay(for: asOf)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        var cursor: Date
        if got(today) { cursor = today }
        else if let yesterday, got(yesterday) { cursor = yesterday }
        else { return 0 }

        var streak = 0
        while got(cursor) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }
}

/// A day's daylight split into the windows that matter for the alertness curve.
public struct DaylightDay: Sendable, Equatable {
    /// Total minutes of daylight today.
    public let total: Double
    /// Minutes in the circadian-critical window — the first hours after waking.
    public let morning: Double
    /// Minutes across the afternoon (~12:00–17:00).
    public let afternoon: Double
    /// Minutes in the evening (~17:00–21:00) — late light can delay the clock.
    public let evening: Double

    public init(total: Double, morning: Double, afternoon: Double, evening: Double) {
        self.total = total
        self.morning = morning
        self.afternoon = afternoon
        self.evening = evening
    }

    public static let empty = DaylightDay(total: 0, morning: 0, afternoon: 0, evening: 0)

    /// Bucket intervals into the day's windows. `morning` is wake-relative (the
    /// first `morningWindowHours` after waking); afternoon/evening are clock-based.
    public static func summarize(intervals: [Daylight.Interval], wakeTime: Date,
                                 morningWindowHours: Double = 4, day: Date? = nil,
                                 calendar: Calendar = .current) -> DaylightDay {
        let base = calendar.startOfDay(for: day ?? wakeTime)
        func clock(_ hour: Int) -> Date { base.addingTimeInterval(TimeInterval(hour) * 3600) }
        let morningEnd = wakeTime.addingTimeInterval(morningWindowHours * 3600)
        return DaylightDay(
            total: Daylight.total(intervals),
            morning: Daylight.minutes(in: intervals, from: wakeTime, to: morningEnd),
            afternoon: Daylight.minutes(in: intervals, from: clock(12), to: clock(17)),
            evening: Daylight.minutes(in: intervals, from: clock(17), to: clock(21))
        )
    }
}
