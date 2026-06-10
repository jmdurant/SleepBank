import XCTest
@testable import SleepBankCore

final class StreaksTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func day(_ offset: Int) -> Date {
        let base = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        return cal.date(byAdding: .day, value: offset, to: base)!
    }

    private var today: Date { Date(timeIntervalSince1970: 1_700_000_000) }

    func testEmptyIsZero() {
        XCTAssertEqual(Streaks.consecutiveDays([], asOf: today, calendar: cal), 0)
    }

    func testConsecutiveRun() {
        let marked: Set<Date> = [day(0), day(-1), day(-2)]
        XCTAssertEqual(Streaks.consecutiveDays(marked, asOf: today, calendar: cal), 3)
    }

    func testSurvivesNotMarkedYetToday() {
        let marked: Set<Date> = [day(-1), day(-2)]
        XCTAssertEqual(Streaks.consecutiveDays(marked, asOf: today, calendar: cal), 2)
    }

    func testBreaksOnGap() {
        let marked: Set<Date> = [day(0), day(-2)]
        XCTAssertEqual(Streaks.consecutiveDays(marked, asOf: today, calendar: cal), 1)
    }

    func testZeroWhenLastMarkTooOld() {
        let marked: Set<Date> = [day(-3)]
        XCTAssertEqual(Streaks.consecutiveDays(marked, asOf: today, calendar: cal), 0)
    }

    func testNormalizesSubDayTimestamps() {
        // Two marks on the same day (different times) count once.
        let marked: Set<Date> = [day(0).addingTimeInterval(3600), day(0).addingTimeInterval(7200)]
        XCTAssertEqual(Streaks.consecutiveDays(marked, asOf: today, calendar: cal), 1)
    }
}
