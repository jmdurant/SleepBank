import Foundation

/// Generic consecutive-day streak over a set of marked days — used for the
/// self-reported "screens off" wind-down streak (iOS doesn't let third-party apps
/// read Screen Time, so this is an honest self-report, mirroring the morning-light
/// streak). Survives "not marked yet today": anchors on today or yesterday.
public enum Streaks {
    public static func consecutiveDays(_ markedDays: Set<Date>, asOf: Date,
                                       calendar: Calendar = .current) -> Int {
        let days = Set(markedDays.map { calendar.startOfDay(for: $0) })
        guard !days.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: asOf)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        var cursor: Date
        if days.contains(today) {
            cursor = today
        } else if let yesterday, days.contains(yesterday) {
            cursor = yesterday
        } else {
            return 0
        }

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }
}
