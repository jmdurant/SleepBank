import XCTest
@testable import SleepBankCore

final class AlertnessRhythmTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// A date at a given clock hour on a fixed reference day (UTC).
    private func at(_ hour: Double) -> Date {
        let base = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        return base.addingTimeInterval(hour * 3600)
    }

    private func rhythm(debt: Double, naps: [AlertnessRhythm.Nap] = []) -> AlertnessRhythm {
        AlertnessRhythm(wakeTime: at(7), sleepDebt: debt, naps: naps, calendar: cal)
    }

    func testLevelsStayInUnitRange() {
        let r = rhythm(debt: 0.3)
        for h in stride(from: 7.0, through: 23.0, by: 0.5) {
            let v = r.level(at: at(h))
            XCTAssert(v >= 0 && v <= 1, "level \(v) out of range at \(h)h")
        }
    }

    func testLessOvernightSleepLowersTheWholeCurve() {
        let rested = rhythm(debt: 0.06)
        let tired = rhythm(debt: 0.45)
        for h in stride(from: 8.0, through: 22.0, by: 1.0) {
            XCTAssertLessThan(tired.level(at: at(h)), rested.level(at: at(h)),
                              "a short night should sit lower at \(h)h")
        }
    }

    func testAfternoonDipIsBelowTheEveningWakeMaintenanceZone() {
        let r = rhythm(debt: 0.1)
        // ~15:30 post-lunch dip should be below the ~19:00 second wind.
        XCTAssertLessThan(r.level(at: at(15.5)), r.level(at: at(19.0)))
        // …and below late morning, i.e. a genuine dip.
        XCTAssertLessThan(r.level(at: at(15.5)), r.level(at: at(12.0)))
    }

    func testNightIsLowerThanMidday() {
        let r = rhythm(debt: 0.1)
        XCTAssertLessThan(r.level(at: at(4.0)), r.level(at: at(12.0)))
    }

    func testNapLiftsAlertnessThenRejoinsBaseline() {
        let r = rhythm(debt: 0.3)
        let napAt = at(14.0)
        // Shortly after a nap, projected alertness exceeds the baseline.
        let soon = at(14.75)
        XCTAssertGreaterThan(r.level(at: soon, withNapAt: napAt, type: .power),
                             r.level(at: soon))
        // Hours later the lift has faded — the curves rejoin.
        let later = at(20.0)
        XCTAssertEqual(r.level(at: later, withNapAt: napAt, type: .power),
                       r.level(at: later), accuracy: 0.02)
    }

    func testCycleNapLiftsMoreThanPowerNap() {
        let r = rhythm(debt: 0.3)
        let napAt = at(14.0)
        // Measure after both naps have ended (power ~14:18, cycle ~15:30).
        let after = at(16.0)
        let powerLift = r.level(at: after, withNapAt: napAt, type: .power) - r.level(at: after)
        let cycleLift = r.level(at: after, withNapAt: napAt, type: .cycle) - r.level(at: after)
        XCTAssertGreaterThan(cycleLift, powerLift)
    }

    func testReadingsSpanTheRequestedWindow() {
        let r = rhythm(debt: 0.2)
        let readings = r.readings(from: at(7), to: at(23), step: 3600)
        XCTAssertEqual(readings.count, 17)              // 7…23 inclusive, hourly
        XCTAssertEqual(readings.first?.date, at(7))
        XCTAssertEqual(readings.last?.date, at(23))
    }

    func testShortNightFlagFromSleep() {
        let short = AlertnessRhythm.fromSleep(wakeTime: at(6), sleptHours: 5.0,
                                              typicalHours: 7.5, now: at(9), calendar: cal)
        XCTAssertTrue(short.isShortNight)
        let fine = AlertnessRhythm.fromSleep(wakeTime: at(6), sleptHours: 7.5,
                                             typicalHours: 7.5, now: at(9), calendar: cal)
        XCTAssertFalse(fine.isShortNight)
        // A short night carries more start-of-day pressure.
        XCTAssertGreaterThan(short.sleepDebt, fine.sleepDebt)
    }
}
