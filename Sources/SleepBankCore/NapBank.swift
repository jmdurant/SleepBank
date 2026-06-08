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
}
