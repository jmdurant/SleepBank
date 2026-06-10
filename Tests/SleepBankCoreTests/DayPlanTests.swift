import XCTest
@testable import SleepBankCore

final class DayPlanTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func at(_ hour: Double) -> Date {
        let base = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        return base.addingTimeInterval(hour * 3600)
    }

    private func rhythm(debt: Double, lightDose: Double = 0, moveDose: Double = 0) -> AlertnessRhythm {
        AlertnessRhythm(wakeTime: at(7), sleepDebt: debt, isShortNight: debt > 0.25,
                        morningLightDose: lightDose, morningActivityDose: moveDose, calendar: cal)
    }

    func testShortNightStartsLowerAndIsFlagged() {
        let rested = DayPlan.build(rhythm: rhythm(debt: 0.06), now: at(8), calendar: cal)
        let tired = DayPlan.build(rhythm: rhythm(debt: 0.45), now: at(8), calendar: cal)
        XCTAssertTrue(tired.isShortNight)
        XCTAssertLessThan(tired.startingLevel, rested.startingLevel)
    }

    func testMorningSuggestsLightWhenNotYetGotten() {
        let plan = DayPlan.build(rhythm: rhythm(debt: 0.3, lightDose: 0), now: at(8), calendar: cal)
        let light = plan.items.first { $0.kind == .morningLight }
        XCTAssertNotNil(light)
        XCTAssertEqual(light?.done, false)
    }

    func testMorningLightShownAsDoneWhenGotten() {
        let plan = DayPlan.build(rhythm: rhythm(debt: 0.3, lightDose: 1), now: at(13), calendar: cal)
        let light = plan.items.first { $0.kind == .morningLight }
        XCTAssertEqual(light?.done, true)   // shown even past morning, as a ✓
    }

    func testNapSuggestedBeforeTheDipOnAShortDay() {
        let plan = DayPlan.build(rhythm: rhythm(debt: 0.4), now: at(9), calendar: cal)
        XCTAssertNotNil(plan.dipTime)
        XCTAssertNotNil(plan.suggestedNap)
        if let nap = plan.suggestedNap, let dip = plan.dipTime {
            XCTAssertLessThan(nap, dip)              // nap is before the dip
        }
        XCTAssertTrue(plan.items.contains { $0.kind == .nap })
    }

    func testNoNapSuggestedOnceTheDipHasPassed() {
        let plan = DayPlan.build(rhythm: rhythm(debt: 0.4), now: at(19), calendar: cal)
        XCTAssertNil(plan.dipTime)                   // dip is behind us
        XCTAssertNil(plan.suggestedNap)
        XCTAssertFalse(plan.items.contains { $0.kind == .nap })
        XCTAssertTrue(plan.items.contains { $0.kind == .windDown })
    }

    func testSuggestedNapIsNotInThePast() {
        // It's already 2:30pm, near the dip — the nap suggestion clamps to "now".
        let plan = DayPlan.build(rhythm: rhythm(debt: 0.4), now: at(14.5), calendar: cal)
        if let nap = plan.suggestedNap {
            XCTAssertGreaterThanOrEqual(nap, at(14.5))
        }
    }

    func testNapAvoidsACalendarConflict() {
        // Ideal nap is ~40 min before the dip; book that ideal slot and the nap moves.
        let r = rhythm(debt: 0.4)
        let noConflict = DayPlan.build(rhythm: r, now: at(9), calendar: cal)
        guard let ideal = noConflict.suggestedNap else { return XCTFail("expected a nap") }

        let meeting = DateInterval(start: ideal, duration: 60 * 60)   // booked over the ideal slot
        let withConflict = DayPlan.build(rhythm: r, now: at(9), busy: [meeting], calendar: cal)

        XCTAssertNotNil(withConflict.suggestedNap)
        XCTAssertNotEqual(withConflict.suggestedNap, ideal)          // moved
        if let nap = withConflict.suggestedNap {
            let slot = DateInterval(start: nap, duration: 30 * 60)
            XCTAssertFalse(meeting.intersects(slot))                  // no longer overlaps
        }
        XCTAssertFalse(withConflict.napBlockedByCalendar)
    }

    func testNapBlockedWhenAfternoonFullyBooked() {
        let r = rhythm(debt: 0.4)
        // Book the whole window the nap could land in.
        let booked = DateInterval(start: at(9), end: at(18))
        let plan = DayPlan.build(rhythm: r, now: at(9), busy: [booked], calendar: cal)
        XCTAssertNil(plan.suggestedNap)
        XCTAssertTrue(plan.napBlockedByCalendar)
        XCTAssertFalse(plan.items.contains { $0.kind == .nap })
    }

    func testNoBusyMeansUnchangedNap() {
        let r = rhythm(debt: 0.4)
        let a = DayPlan.build(rhythm: r, now: at(9), calendar: cal).suggestedNap
        let b = DayPlan.build(rhythm: r, now: at(9), busy: [], calendar: cal).suggestedNap
        XCTAssertEqual(a, b)
    }

    func testItemsAreChronological() {
        let plan = DayPlan.build(rhythm: rhythm(debt: 0.4), now: at(8), calendar: cal)
        let times = plan.items.map { $0.time ?? at(8) }
        XCTAssertEqual(times, times.sorted())
    }
}
