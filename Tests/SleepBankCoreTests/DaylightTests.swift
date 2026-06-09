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
}
