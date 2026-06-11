import XCTest
@testable import SleepBankCore

final class DaylightTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func at(_ hour: Double) -> Date {
        let base = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        return base.addingTimeInterval(hour * 3600)
    }

    private func interval(_ startHour: Double, _ endHour: Double, minutes: Double? = nil) -> Daylight.Interval {
        let m = minutes ?? (endHour - startHour) * 60   // default: full span is daylight
        return Daylight.Interval(start: at(startHour), end: at(endHour), minutes: m)
    }

    func testTotalSumsMinutes() {
        let ivs = [interval(8, 8.5), interval(13, 13.25)]   // 30 + 15
        XCTAssertEqual(Daylight.total(ivs), 45, accuracy: 0.001)
    }

    func testMinutesInRangeCountsOnlyOverlap() {
        let ivs = [interval(8, 9)]                          // 60 min, 08:00–09:00
        XCTAssertEqual(Daylight.minutes(in: ivs, from: at(8), to: at(9)), 60, accuracy: 0.001)
        XCTAssertEqual(Daylight.minutes(in: ivs, from: at(10), to: at(11)), 0, accuracy: 0.001)
    }

    func testIntervalStraddlingBoundarySplitsProportionally() {
        // 08:00–09:00, 60 daylight min; window cuts it at 08:30 → half attributed.
        let ivs = [interval(8, 9)]
        XCTAssertEqual(Daylight.minutes(in: ivs, from: at(8), to: at(8.5)), 30, accuracy: 0.001)
        XCTAssertEqual(Daylight.minutes(in: ivs, from: at(8.5), to: at(9)), 30, accuracy: 0.001)
    }

    func testPartialDaylightMinutesAreDistributedAcrossSpan() {
        // A 60-min span but only 20 daylight minutes; half the span → 10 min.
        let ivs = [interval(8, 9, minutes: 20)]
        XCTAssertEqual(Daylight.minutes(in: ivs, from: at(8), to: at(8.5)), 10, accuracy: 0.001)
    }

    func testSummarizeBucketsMorningAfternoonEvening() {
        let wake = at(6.5)
        let ivs = [
            interval(7, 7.5),     // 30 min, within wake+4h (→ morning)
            interval(13, 13.5),   // 30 min afternoon
            interval(18, 18.25),  // 15 min evening
        ]
        let day = DaylightDay.summarize(intervals: ivs, wakeTime: wake, calendar: cal)
        XCTAssertEqual(day.total, 75, accuracy: 0.001)
        XCTAssertEqual(day.morning, 30, accuracy: 0.001)
        XCTAssertEqual(day.afternoon, 30, accuracy: 0.001)
        XCTAssertEqual(day.evening, 15, accuracy: 0.001)
    }

    func testWindowsTileTheDaySoPartsSumToTotal() {
        // Regression for the reported bug: the late-morning hour (wake+4h → noon) fell
        // in no bucket, so total (28) > morning + afternoon + evening (18 + 4 + 0).
        let wake = at(7)                          // morning window ends 11:00
        let ivs = [
            interval(8, 8.3, minutes: 18),        // morning
            interval(11.5, 11.6, minutes: 6),     // the old gap (11:00–12:00) — was dropped
            interval(14, 14.1, minutes: 4),       // afternoon
        ]
        let day = DaylightDay.summarize(intervals: ivs, wakeTime: wake, calendar: cal)
        XCTAssertEqual(day.morning + day.afternoon + day.evening, day.total, accuracy: 0.001)
        XCTAssertEqual(day.total, 28, accuracy: 0.001)
        XCTAssertEqual(day.morning, 18, accuracy: 0.001)
        XCTAssertEqual(day.afternoon, 10, accuracy: 0.001)   // 4 + the recovered 6
        XCTAssertEqual(day.evening, 0, accuracy: 0.001)
    }

    func testLateRiserDoesNotDoubleCountMorningIntoAfternoon() {
        // wake 09:00 → morning window ends 13:00. A 12:30 interval is morning only;
        // afternoon starts where the morning window ends, so no overlap.
        let day = DaylightDay.summarize(intervals: [interval(12.5, 13, minutes: 30)],
                                        wakeTime: at(9), calendar: cal)
        XCTAssertEqual(day.morning, 30, accuracy: 0.001)
        XCTAssertEqual(day.afternoon, 0, accuracy: 0.001)
        XCTAssertEqual(day.morning + day.afternoon + day.evening, day.total, accuracy: 0.001)
    }

    func testLateEveningLightIsCounted() {
        // Summer dusk at ~21:30 used to be dropped (evening capped at 21:00).
        let day = DaylightDay.summarize(intervals: [interval(21.5, 21.75, minutes: 15)],
                                        wakeTime: at(7), calendar: cal)
        XCTAssertEqual(day.evening, 15, accuracy: 0.001)
        XCTAssertEqual(day.total, 15, accuracy: 0.001)
    }

    func testMorningWindowIsWakeRelative() {
        // A late riser (wake 10:00): 11:00 light is "morning," not afternoon.
        let ivs = [interval(11, 11.5)]
        let day = DaylightDay.summarize(intervals: ivs, wakeTime: at(10), calendar: cal)
        XCTAssertEqual(day.morning, 30, accuracy: 0.001)
    }

    func testEmptyIntervalsGiveEmptyDay() {
        let day = DaylightDay.summarize(intervals: [], wakeTime: at(7), calendar: cal)
        XCTAssertEqual(day, .empty)
    }

    // MARK: - Morning-light streak

    /// A daylight interval on the day `dayOffset` (0 = today) at a given clock hour.
    private func dayInterval(dayOffset: Int, hour: Double, minutes: Double) -> Daylight.Interval {
        let base = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let day = cal.date(byAdding: .day, value: dayOffset, to: base)!
        let start = day.addingTimeInterval(hour * 3600)
        return Daylight.Interval(start: start, end: start.addingTimeInterval(minutes * 60), minutes: minutes)
    }

    private var today: Date { Date(timeIntervalSince1970: 1_700_000_000) }

    func testMorningStreakCountsConsecutiveDaysWithMorningLight() {
        let ivs = [
            dayInterval(dayOffset: 0, hour: 8, minutes: 15),
            dayInterval(dayOffset: -1, hour: 7.5, minutes: 20),
            dayInterval(dayOffset: -2, hour: 9, minutes: 12),
        ]
        XCTAssertEqual(Daylight.morningStreak(intervals: ivs, asOf: today, targetMinutes: 10, calendar: cal), 3)
    }

    func testMorningStreakSurvivesNoLightYetToday() {
        let ivs = [
            dayInterval(dayOffset: -1, hour: 8, minutes: 15),
            dayInterval(dayOffset: -2, hour: 8, minutes: 15),
        ]
        XCTAssertEqual(Daylight.morningStreak(intervals: ivs, asOf: today, targetMinutes: 10, calendar: cal), 2)
    }

    func testMorningStreakIgnoresAfternoonLightAndSubThresholdMornings() {
        let ivs = [
            dayInterval(dayOffset: 0, hour: 14, minutes: 60),   // afternoon — doesn't count
            dayInterval(dayOffset: -1, hour: 8, minutes: 4),    // below 10-min target
        ]
        XCTAssertEqual(Daylight.morningStreak(intervals: ivs, asOf: today, targetMinutes: 10, calendar: cal), 0)
    }

    func testMorningStreakBreaksOnAMissedDay() {
        let ivs = [
            dayInterval(dayOffset: 0, hour: 8, minutes: 15),
            // gap at -1
            dayInterval(dayOffset: -2, hour: 8, minutes: 15),
        ]
        XCTAssertEqual(Daylight.morningStreak(intervals: ivs, asOf: today, targetMinutes: 10, calendar: cal), 1)
    }
}
