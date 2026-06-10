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

    func testItemsAreChronological() {
        let plan = DayPlan.build(rhythm: rhythm(debt: 0.4), now: at(8), calendar: cal)
        let times = plan.items.map { $0.time ?? at(8) }
        XCTAssertEqual(times, times.sorted())
    }
}
