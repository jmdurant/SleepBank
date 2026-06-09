import Foundation

/// The "sleep bank" — deliberately *descriptive*, not a model. It just totals the
/// sleep your naps gave back so you can see it accumulate. No deposit formulas,
/// no circadian point-scoring: plain, honest sums and trends.
public enum NapBank {

    /// Minutes actually asleep across naps that started on the given day.
    public static func minutesAsleep(on day: Date, in records: [NapRecord],
                                     calendar: Calendar = .current) -> Int {
        let seconds = records
            .filter { calendar.isDate($0.start, inSameDayAs: day) }
            .reduce(0.0) { $0 + $1.asleepDuration }
        return Int(seconds / 60)
    }

    /// Number of naps that started on the given day.
    public static func count(on day: Date, in records: [NapRecord],
                             calendar: Calendar = .current) -> Int {
        records.filter { calendar.isDate($0.start, inSameDayAs: day) }.count
    }

    /// Minutes asleep across naps in the 7 days ending at `day` (inclusive).
    public static func minutesAsleepLast7Days(endingAt day: Date, in records: [NapRecord],
                                              calendar: Calendar = .current) -> Int {
        guard let weekStart = calendar.date(byAdding: .day, value: -6,
                                            to: calendar.startOfDay(for: day)) else { return 0 }
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) ?? day
        let seconds = records
            .filter { $0.start >= weekStart && $0.start < dayEnd }
            .reduce(0.0) { $0 + $1.asleepDuration }
        return Int(seconds / 60)
    }

    /// Consecutive days, counting back from `day`, with at least one nap that
    /// actually reached sleep (onset detected). The honest gamification: it counts
    /// what really happened, no points or formulas. Not having napped *yet* today
    /// doesn't break a streak that ran through yesterday — we anchor on the most
    /// recent napped day if that's today or yesterday, otherwise the streak is 0.
    public static func currentStreak(asOf day: Date, in records: [NapRecord],
                                     calendar: Calendar = .current) -> Int {
        let nappedDays = Set(records
            .filter { $0.onset != nil }
            .map { calendar.startOfDay(for: $0.start) })
        guard !nappedDays.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: day)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        var cursor: Date
        if nappedDays.contains(today) {
            cursor = today
        } else if let yesterday, nappedDays.contains(yesterday) {
            cursor = yesterday
        } else {
            return 0
        }

        var streak = 0
        while nappedDays.contains(cursor) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }
}
