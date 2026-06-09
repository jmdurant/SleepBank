import XCTest
@testable import SleepBankCore

final class AlertnessChargeTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func nap(type: NapType, asleepMinutes: Int, endedMinutesAgo: Int,
                     onset: Bool = true, now: Date) -> NapRecord {
        let end = now.addingTimeInterval(TimeInterval(-endedMinutesAgo * 60))
        let onsetDate = onset ? end.addingTimeInterval(TimeInterval(-asleepMinutes * 60)) : nil
        let start = (onsetDate ?? end).addingTimeInterval(-120)
        return NapRecord(start: start, end: end, type: type,
                         onset: onsetDate, wakeReason: .reachedTarget)
    }

    func testNoNapMeansEmpty() {
        XCTAssertEqual(AlertnessCharge.current(now: base, lastNap: nil), .empty)
    }

    func testNapWithoutOnsetGivesNoCharge() {
        let n = nap(type: .power, asleepMinutes: 18, endedMinutesAgo: 1, onset: false, now: base)
        XCTAssertEqual(AlertnessCharge.current(now: base, lastNap: n), .empty)
    }

    func testFreshFullPowerNapIsNearPeak() {
        let n = nap(type: .power, asleepMinutes: 18, endedMinutesAgo: 0, now: base)
        let c = AlertnessCharge.current(now: base, lastNap: n)
        // Full nap (>= target), just woke → ~peak (0.85).
        XCTAssertEqual(c.level, 0.85, accuracy: 0.02)
        XCTAssertEqual(c.source, .power)
        XCTAssertEqual(c.minutesRemaining, 125, accuracy: 1)
    }

    func testChargeFadesLinearlyToZeroAtWindowEnd() {
        let n = nap(type: .power, asleepMinutes: 18, endedMinutesAgo: 0, now: base)
        // Halfway through the 125-min window → about half of peak.
        let mid = base.addingTimeInterval(125 * 60 / 2)
        let c = AlertnessCharge.current(now: mid, lastNap: n)
        XCTAssertEqual(c.level, 0.85 * 0.5, accuracy: 0.03)
        // Past the window → empty.
        let after = base.addingTimeInterval(130 * 60)
        XCTAssertEqual(AlertnessCharge.current(now: after, lastNap: n), .empty)
    }

    func testCycleNapPeaksHigherAndLastsLonger() {
        let n = nap(type: .cycle, asleepMinutes: 90, endedMinutesAgo: 0, now: base)
        let c = AlertnessCharge.current(now: base, lastNap: n)
        XCTAssertEqual(c.level, 1.0, accuracy: 0.02)
        XCTAssertEqual(c.minutesRemaining, 180, accuracy: 1)
    }

    func testShortMicroSleepGivesSmallerBoostThanFullNap() {
        let micro = nap(type: .power, asleepMinutes: 4, endedMinutesAgo: 0, now: base)
        let full = nap(type: .power, asleepMinutes: 18, endedMinutesAgo: 0, now: base)
        let microLevel = AlertnessCharge.current(now: base, lastNap: micro).level
        let fullLevel = AlertnessCharge.current(now: base, lastNap: full).level
        XCTAssertLessThan(microLevel, fullLevel)
        XCTAssertGreaterThan(microLevel, 0)
    }

    func testFutureNapEndIsIgnored() {
        let n = nap(type: .power, asleepMinutes: 18, endedMinutesAgo: -10, now: base) // ends in future
        XCTAssertEqual(AlertnessCharge.current(now: base, lastNap: n), .empty)
    }
}
