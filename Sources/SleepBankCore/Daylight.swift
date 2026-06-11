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
    /// Minutes from the end of the morning window to the evening (≤17:00).
    public let afternoon: Double
    /// Minutes in the evening (from ~17:00 to end of day) — late light can delay the clock.
    public let evening: Double

    public init(total: Double, morning: Double, afternoon: Double, evening: Double) {
        self.total = total
        self.morning = morning
        self.afternoon = afternoon
        self.evening = evening
    }

    public static let empty = DaylightDay(total: 0, morning: 0, afternoon: 0, evening: 0)

    /// Bucket intervals into the day's windows. The windows **tile the whole day**,
    /// so the parts always sum to `total` (no minutes leak into a gap and none are
    /// double-counted). `morning` ends a wake-relative `morningWindowHours` after
    /// waking (its start is the day's start — any pre-wake light is negligible since
    /// daylight isn't logged while asleep); `afternoon` runs from there to the
    /// evening; `evening` runs from ~17:00 to end of day. Afternoon/evening starts are
    /// clamped to the prior window's end, so a late riser (wake + window past 17:00)
    /// produces no overlap.
    public static func summarize(intervals: [Daylight.Interval], wakeTime: Date,
                                 morningWindowHours: Double = 4, day: Date? = nil,
                                 calendar: Calendar = .current) -> DaylightDay {
        let base = calendar.startOfDay(for: day ?? wakeTime)
        func clock(_ hour: Int) -> Date { base.addingTimeInterval(TimeInterval(hour) * 3600) }
        let morningEnd = wakeTime.addingTimeInterval(morningWindowHours * 3600)
        let eveningStart = max(clock(17), morningEnd)
        let dayEnd = clock(24)
        let morning = Daylight.minutes(in: intervals, from: base, to: morningEnd)
        let afternoon = Daylight.minutes(in: intervals, from: morningEnd, to: eveningStart)
        let evening = Daylight.minutes(in: intervals, from: eveningStart, to: dayEnd)
        return DaylightDay(total: morning + afternoon + evening,
                           morning: morning, afternoon: afternoon, evening: evening)
    }
}
