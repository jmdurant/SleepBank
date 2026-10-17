import XCTest
@testable import SleepBankCore

final class AlertnessSnapshotTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c
    }
    private let day = Date(timeIntervalSince1970: 1_700_006_400)
    private func snapshot(sleepDay: Date?) -> AlertnessSnapshot {
        .init(rhythm: AlertnessRhythm(wakeTime: day, sleepDebt: 0.4, circadianShiftHours: 2),
              morningLightStreak: 3, updated: day, sleepDay: sleepDay)
    }
    func testMissingBasisCannotProduceScore() {
        XCTAssertNil(snapshot(sleepDay: nil).rebuild(asOf: day, calendar: cal))
    }
    func testYesterdayIsNotRedatedIntoTodaysScore() {
        XCTAssertNil(snapshot(sleepDay: day).rebuild(asOf: day.addingTimeInterval(86400), calendar: cal))
    }
    func testCurrentSnapshotPreservesDebtAndChronotype() throws {
        let result = try XCTUnwrap(snapshot(sleepDay: day).rebuild(asOf: day, calendar: cal))
        XCTAssertEqual(result.sleepDebt, 0.4)
        XCTAssertEqual(result.circadianShiftHours, 2)
    }
    func testRefreshingOldSleepDoesNotMakeItCurrent() {
        var snap = snapshot(sleepDay: day.addingTimeInterval(-86400))
        snap.updated = day
        XCTAssertNil(snap.rebuild(asOf: day, calendar: cal))
    }
    func testLegacySnapshotRequiresFreshSleepBasis() throws {
        let data = try JSONEncoder().encode(snapshot(sleepDay: day))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "sleepDay")
        let old = try JSONDecoder().decode(AlertnessSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.rebuild(asOf: day, calendar: cal))
    }
}
