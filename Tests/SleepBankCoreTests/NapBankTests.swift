import XCTest
@testable import SleepBankCore

final class NapBankTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func nap(startHour: Int, asleepMinutes: Int, dayOffset: Int = 0) -> NapRecord {
        let base = Date(timeIntervalSince1970: 1_700_000_000)   // fixed reference
        let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: base))!
        let start = cal.date(byAdding: .hour, value: startHour, to: day)!
        let onset = start.addingTimeInterval(120)               // onset 2 min in
        let end = onset.addingTimeInterval(TimeInterval(asleepMinutes * 60))
        return NapRecord(start: start, end: end, type: .power, onset: onset, wakeReason: .reachedTarget)
    }

    func testMinutesAsleepSumsSameDayNaps() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let records = [nap(startHour: 13, asleepMinutes: 18), nap(startHour: 16, asleepMinutes: 20)]
        XCTAssertEqual(NapBank.minutesAsleep(on: base, in: records, calendar: cal), 38)
        XCTAssertEqual(NapBank.count(on: base, in: records, calendar: cal), 2)
    }

    func testNapWithoutOnsetContributesZero() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let start = cal.date(byAdding: .hour, value: 14, to: cal.startOfDay(for: base))!
        let noOnset = NapRecord(start: start, end: start.addingTimeInterval(1800),
                                type: .power, onset: nil, wakeReason: .ceiling)
        XCTAssertEqual(NapBank.minutesAsleep(on: base, in: [noOnset], calendar: cal), 0)
        XCTAssertEqual(NapBank.count(on: base, in: [noOnset], calendar: cal), 1)
    }

    func testSevenDayTotalIncludesWeekAndExcludesOlder() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let records = [
            nap(startHour: 13, asleepMinutes: 20, dayOffset: 0),
            nap(startHour: 13, asleepMinutes: 15, dayOffset: -6),   // edge of window
            nap(startHour: 13, asleepMinutes: 99, dayOffset: -7),   // just outside
        ]
        XCTAssertEqual(NapBank.minutesAsleepLast7Days(endingAt: base, in: records, calendar: cal), 35)
    }

    func testRecordRoundTripsThroughCodable() throws {
        let original = nap(startHour: 13, asleepMinutes: 18)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NapRecord.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
